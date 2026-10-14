# Hekili for WoW Forever: virtual game API skeleton and cleanup. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Hekili load on the WoW Forever client (interface 16001) with no Lua errors, with every game read going through a vendored facade library whose stubs replace what is secret or removed on Forever, and with the retail-only content archived or removed.

**Architecture:** A LibStub library `VirtualGameAPI-1.0` (short name `VGA`) mirrors the game API names Hekili reads. Each entry is `passthrough` (the real function behind one `invoke` seam) or `stub` (a fixed Hekili-shaped non-secret value). Hekili files get a block of file-top locals (`local UnitPower = VGA.UnitPower`, `local C_Spell = VGA.C_Spell`) right after `local addon, ns = ...`, so call sites stay untouched. Then the expansion folders move to `archive/`, the retail-only engine and Options content is deleted, the libraries are vendored, and the TOC targets 16001.

**Tech Stack:** Lua 5.1 (WoW), LibStub, busted (headless tests for the library), luacheck, `wow` MCP server tools (`wow_api_search`, `wow_lua_lint`, `wow_toc_validate`, `wow_xml_validate`), lua-language-server.

**Spec:** the session brief (reproduced in the user's task message) plus the inventory documents:
`~/src/TacoDogForever/docs/research/2026-10-14-hekili-virtual-state-feasibility.md` (sections A, C.5, E),
`git show origin/research/forever-revival:docs/research/03-cleanup-inventory.md` and `01-api-inventory.md`,
`~/src/TacoDogForever/docs/research/2026-10-14-hekili-libraries-for-forever.md`,
`~/src/TacoDogForever/docs/research/2026-10-13-probe-session-W-results.md` §4.

## Execution order

Tasks run 1 to 10, then **19** (vendoring and TOC), then Checkpoint A, then 11 to 18, 20 (Checkpoint B), 21.
Reason: the checkout cannot load without the libraries. The brief's step order assumed a loadable checkout at
Checkpoint A; this is the smallest change that makes it true.

**Library policy (user decision, 2026-10-14):** every library `embeds.xml` includes is vendored, whether or not
its upstream declares Forever support. A library is dropped only when it proves invalid in game (a load error or
a forbidden action), and then in its own commit with the evidence in `docs/forever-cleanup.md`. No library
call sites are removed in this plan.

## Global Constraints

- Repository: `~/src/hekili`, worktree `~/src/hekili/.claude/worktrees/forever-cleanup`, branch `forever-cleanup` (base `forever` at `36daec38`). Push to `origin` after each commit. Never push to `forever` or `classic`, never force-push, never merge. Git from WSL only.
- Commit messages end with `Co-Authored-By: Claude <model name> <noreply@anthropic.com>` naming the model that wrote the commit (for example `Claude Opus 4.5`).
- Do NOT build virtual state (Phase 1), do NOT change the bodies of the secrecy-zone code paths (cooldown metatable `State.lua:3258-3535`, `ScrapeUnitAuras` `State.lua:5956-6173`, `state.reset` `State.lua:6787-7136`, the `UNIT_POWER`, `UNIT_AURA` and combat-log handlers in `Events.lua`, `Targets.lua` combat-log and time-to-die code, `UI.lua` cooldown arithmetic `1495-1516, 1700-1746`, spec detection `Classes.lua:4091-4378`), do NOT write a Forever class pack, do NOT remove the version gates (`Hekili.lua:26-54`, `Core.lua:203`; those are Phase 3b).
- Do not override `_G` or the real `C_*` tables, do not `setfenv` whole files. File-top locals only.
- Stubs never return a secret value. Stub results are shared constant tables; callers must not mutate them (Hekili only reads them).
- Performance: no new tables or closures per call in the library's passthrough or stub paths.
- Clean room: do not copy code from `~/src/TacoDogForever` into this repository.
- Tools: luacheck and busted live in `~/src/TacoDogForever/.lua/bin/` (`LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`, `BUSTED=~/src/TacoDogForever/.lua/bin/busted`); `luac5.1 -p` for compile checks; `lua-language-server` from mise. `wow` MCP tools default to flavor `forever`.
- Every task ends with: `luac5.1 -p` on touched Lua files, `$LUACHECK` clean on touched files (with the task's `.luacheckrc`), `wow_lua_lint` clean on touched loaded files, a commit, a push.
- Archived files (`archive/`) are never loaded, linted or edited.
- Reports to the user are at most one page.

## Review Focus

1. **A file-top local block that compiles but breaks a function's upvalue limit (60) or the chunk's local limit (200).** `luac5.1 -p` must pass for every redirected file; if it fails, the fallback is `VGA.Name(` at the call sites of that one function (Task 5 step 5). Test: `luac5.1 -p` in every redirection task.
2. **A passthrough whose real function is nil on Forever** (deprecated shims such as `SpellIsSelfBuff`, bare `GetItemInfo`). The library must not throw at load; it records `missing` and returns nil. Test: Task 3 test 4.
3. **A stub returning "nothing" where Hekili divides or indexes.** `UnitPowerMax` stays passthrough (plain on Forever). Stub zeros reach `res.max / ...` only behind `if res.max > 0` (`State.lua:6902`); other sites are listed in `docs/forever-facade-notes.md` (Task 10), not patched.
4. **Archived files still referenced after the move**: a TOC line, an XML include, or an `ns.X` function defined only in an archived file and called from the engine. Test: Task 11 step 6 grep and Task 20 dangling-reference sweep.
5. **A vendored library that refuses to load or acts forbidden on 16001** (SpellFlashCore returns early; others unknown). Test: Task 19 records each library's load gate in `Libs/CREDITS.md`; Checkpoint B separates library failures from Hekili failures; a library is dropped only on in-game evidence.

---

## Part 1: the virtual game API library

### Task 1: Lint configuration that can be clean

**Files:**
- Modify: `.luacheckrc` (replace the 537 KB retail file)
- Modify: `.gitignore` (add `.claude/`)

**Interfaces:**
- Produces: a `.luacheckrc` where the only warnings on the loaded root files are `W113 accessing undefined variable` for game API names (which Tasks 4 to 9 remove). Everything else is clean.

- [ ] **Step 1: Record the baseline**

Run (in the worktree):
```bash
FILES="Hekili.lua Utils.lua Formatting.lua MultilineEditor.lua Constants.lua State.lua Events.lua Classes.lua Targets.lua UI.lua Scripts.lua Core.lua Options/Options.lua Options/ChatCommands.lua Options/DevTools.lua UI/PopupSlider.lua"
$LUACHECK --formatter plain --codes $FILES | grep -oE "\(W[0-9]+\)" | sort | uniq -c | sort -rn
```
Expected: about 560 warnings, 328 of them W113.

- [ ] **Step 2: Write the new `.luacheckrc`**

```lua
-- Lint for the Forever branch. Game API names are deliberately NOT declared here:
-- every game read must go through LibStub("VirtualGameAPI-1.0") (see tools/check_api_reads.sh),
-- so a bare game API name shows up as W113 "accessing undefined variable".
std = "lua51"
max_line_length = false
codes = true

exclude_files = {
    "Libs/",
    "archive/",
    ".claude/",
    ".luacheckrc",
    -- expansion folders: archived in Task 11, never redirected
    "TheWarWithin/", "Dragonflight/", "Shadowlands/", "BfA/", "Legion/", "Wrath/", "Cataclysm/", "TheBurningCrusade/",
}

ignore = {
    "11./SLASH_.*",      -- slash command globals
    "11./BINDING_.*",    -- keybinding header globals
    "211", "212", "213", "214", -- unused locals, arguments, loop variables
    "221", "231",        -- set-but-unused
    "241",               -- mutated-but-unused
    "311", "312", "321", -- value assigned but overwritten / unused
    "4..",               -- shadowing (legacy code style)
    "5..",               -- unused code after return, empty if, etc.
    "6..",               -- whitespace
}

-- Hekili's own globals (written and read)
globals = {
    "Hekili", "HekiliDB", "HekiliEngine", "HekiliDisplayPrimary", "HekiliDisplayAOE", "HekiliDisplayCooldowns",
    "HekiliDisplayDefensives", "HekiliDisplayInterrupts", "HekiliNotification", "HekiliNotificationMover",
    "HekiliNotificationText", "HekiliTooltip", "HekiliCustomEditorInsertLink", "Hekili_Keyhandler",
    "Hekili_GetRecommendedAbility", "Hekili_OnAddonCompartmentClick", "Hekili_OnAddonCompartmentEnter",
    "Hekili_OnAddonCompartmentLeave", "Hekili_ToggleOptions", "Hekili_ToggleMode", "Hekili_TogglePause",
    "Hekili_SnapshotMode", "Hekili_ToggleCooldowns", "Hekili_ToggleDefensives", "Hekili_ToggleInterrupts",
    "Hekili_TogglePotions", "Hekili_ToggleEssences", "Hekili_ToggleCustom1", "Hekili_ToggleCustom2",
    "Hekili_ToggleDisplayMode", "Hekili_FixSpecialization", "HandleSpellData", "BlizzBlue",
}

-- WoW Lua extensions, FrameXML utilities, other addons and constants that are not game-state reads.
read_globals = {
    -- Lua extensions provided by the client
    "wipe", "format", "strupper", "strlower", "strfind", "strsub", "strlen", "strsplit", "strjoin", "strtrim",
    "strmatch", "strrep", "strbyte", "strchar", "gmatch", "gsub", "tostringall", "tinsert", "tremove", "sort",
    "max", "min", "floor", "ceil", "abs", "date", "time", "bit", "debugstack", "debugprofilestop",
    "geterrorhandler", "seterrorhandler", "issecretvalue", "issecrettable", "C_Secrets",
    -- libraries and other addons
    "LibStub", "WeakAuras", "ElvUI", "ConsolePort", "SpellFlashCore", "Masque",
    -- FrameXML (Lua-defined UI utilities, not reads)
    "CreateFrame", "UIParent", "GameTooltip", "GameTooltip_SetTitle", "GameTooltip_AddNormalLine",
    "GetAppropriateTooltip", "UIDropDownMenu_SetDisplayMode", "UIDropDownMenu_AddSeparator",
    "UIDropDownMenu_AddButton", "ToggleDropDownMenu", "UIFrameFadeOut", "PixelUtil", "PlayerUtil", "ExportUtil",
    "ClassTalentImportExportMixin", "Item", "ItemLocation", "Mixin", "hooksecurefunc", "CreateAtlasMarkup",
    "BackdropTemplateMixin", "AddonCompartmentFrame", "DEFAULT_CHAT_FRAME", "ChatFontNormal", "DevTools_Dump",
    "InterfaceOptions_AddCategory", "Screenshot", "SetCVar", "SetOverrideBindingClick", "ClearOverrideBindings",
    "ClearCursor", "C_Timer", "Enum", "RAID_CLASS_COLORS", "NORMAL_FONT_COLOR", "TOOLTIP_UPDATE_TIME",
    "MAX_PLAYER_LEVEL", "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE", "ACCEPT",
    "INVTYPE_WEAPONMAINHAND", "INVSLOT_NECK", "INVSLOT_LAST_EQUIPPED", "ITEM_SPELL_TRIGGER_ONEQUIP",
    "PET_TYPE_DEMON", "BATTLE_PET_NAME_4", "COMBATLOG_OBJECT_REACTION_FRIENDLY",
    "CR_VERSATILITY_DAMAGE_TAKEN", "CR_VERSATILITY_DAMAGE_DONE", "CR_MASTERY", "CR_HASTE_MELEE",
    "CR_CRIT_TAKEN_SPELL", "CR_CRIT_MELEE",
}

-- Names that only exist inside functions run with setfenv( f, state ): APL handlers and class
-- registration code. They are not globals; luacheck cannot see the environment.
local stateEnv = {
    "query_time", "applyBuff", "removeBuff", "applyDebuff", "removeDebuff", "gain", "spend", "buff", "debuff",
    "talent", "spec", "overcap", "health", "haste", "gcd", "equipped", "action", "solo", "settings", "now",
    "moving", "assignAuraToLastCast", "actual_trinket1", "actual_trinket2", "actual_main_hand", "trackAuraRemoval",
    "trackAuraApplication", "toggleSpell", "target", "state", "squawk", "set_bonus", "setCooldown", "safeAbs",
    "next_ation", "name", "listName", "id", "event", "boss", "alphaCheck", "abilitty", "display", "args", "v", "p",
    "val", "treeToString", "QueueRebuildUI",
}
files["Classes.lua"] = { globals = stateEnv }
files["State.lua"] = { globals = stateEnv }
files["Scripts.lua"] = { globals = stateEnv }
files["Core.lua"] = { globals = stateEnv }
files["Events.lua"] = { globals = stateEnv }
files["Options/Options.lua"] = { globals = stateEnv }
files["Options/DevTools.lua"] = { globals = stateEnv }
files["Options/ChatCommands.lua"] = { globals = stateEnv }
files["Targets.lua"] = { globals = stateEnv }
files["UI.lua"] = { globals = stateEnv }
files["Utils.lua"] = { globals = stateEnv }
files["Hekili.lua"] = { globals = stateEnv }
```

Adjust the lists from the actual luacheck output until the only remaining warnings are W113 on game API names (names that `wow_api_search` finds as client API functions, or `C_*` namespaces). Do not add any game API name to `read_globals`. If a W111/W112 (setting an undefined global) names a Hekili global not listed above, add it to `globals`.

- [ ] **Step 3: Verify**

Run: `$LUACHECK $FILES --formatter plain --codes | grep -v W113; echo "---"; $LUACHECK $FILES --formatter plain --codes | grep -c W113`
Expected: nothing before `---`; a count of W113 lines after it (around 300).

- [ ] **Step 4: Commit**

```bash
printf '.claude/\n' >> .gitignore
git add .luacheckrc .gitignore
git commit -m "chore(lint): Forever luacheck config; game API names stay undeclared on purpose"
git push -u origin forever-cleanup
```

### Task 2: The read inventory

**Files:**
- Create: `tools/list_api_reads.sh`
- Create: `tools/api_inventory.txt`
- Create: `docs/forever-facade-notes.md` (first section: the inventory table)

**Interfaces:**
- Produces: `tools/api_inventory.txt`, one name per line, sorted, in the forms `UnitPower` or `C_Spell.GetSpellCooldown` or `AuraUtil.ForEachAura`. This is the list the library must cover (Task 3 tests read it) and the list `tools/check_api_reads.sh` forbids as bare reads (Task 10).
- Produces: `docs/forever-facade-notes.md` section "Inventory" with one row per name: Forever presence (from `wow_api_search`), secrecy class (from probe §4), status (`passthrough` or `stub`), stub shape.

- [ ] **Step 1: Write `tools/list_api_reads.sh`**

```bash
#!/usr/bin/env bash
# Lists the game API names the loaded Hekili files read directly: bare globals (via luacheck W113,
# which ignores strings and comments), C_* and AuraUtil namespace members (via grep), and _G.Name reads.
# Usage: tools/list_api_reads.sh [file ...]   (default: every .lua in Hekili.toc)
set -euo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
if [ $# -gt 0 ]; then files=("$@"); else
    mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
fi
{
    "$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}" 2>/dev/null \
        | grep -oE "accessing undefined variable '[^']+'" | sed -E "s/.*'([^']+)'/\1/" || true
    grep -ohE "\b(C_[A-Za-z]+|AuraUtil)\.[A-Za-z_]+" "${files[@]}" || true
    grep -ohE "_G\.[A-Za-z_]+" "${files[@]}" | sed 's/^_G\.//' || true
} | sort -u
```

`chmod +x tools/list_api_reads.sh`. Run it; it prints about 330 candidate names (Lua extensions, FrameXML names, Hekili globals and state-environment names included).

- [ ] **Step 2: Curate `tools/api_inventory.txt`**

Keep a candidate only if it is a client API function that reads game, character, spell, item, unit, talent, binding or client state. Rules:
- Keep every `C_*.X` member except `C_Timer.*` (not a read). Keep `AuraUtil.ForEachAura`, `AuraUtil.FindAura`, `AuraUtil.UnpackAuraData` (they read aura state).
- Keep every bare `Unit*`, `Get*`, `Is*`, `Has*`, `In*`, `SpellIsSelfBuff`, `CombatLogGetCurrentEventInfo`, `SecureCmdOptionParse`, `GetCVar`, `GetTime`, `GetBuildInfo`, `GetRealmName`, `GetFramerate`, `GetNetStats`, `GetFrameCPUUsage`.
- Drop Lua extensions (`max`, `wipe`, `format`, `date`, `time`, `bit`, `debugstack`, `debugprofilestop`, ...), FrameXML UI utilities and constants (`CreateFrame`, `UIParent`, `GameTooltip`, `PixelUtil`, `PlayerUtil`, `Enum`, `RAID_CLASS_COLORS`, ...), writes (`SetCVar`, `SetOverrideBindingClick`, `ClearOverrideBindings`, `ClearCursor`, `Screenshot`), other addons (`WeakAuras`, `ElvUI`, `ConsolePort`, `SpellFlashCore`, `LibStub`), Hekili's own globals and the state-environment names listed in `.luacheckrc`.
- When unsure whether a name is a client API, run `wow_api_search` for it (flavor `forever`); a documented function or a C-side global is a read.

Expected size: about 190 names. Write them sorted, one per line.

- [ ] **Step 3: Research each name on Forever**

For every name in the inventory, determine with `wow_api_search` (flavor `forever`; use `namespace` to list a whole `C_*` namespace in one call with `limit: 100`) whether the function exists. Record `present`, `absent`, or `undocumented C global` (present in Forever FrameXML per `01-api-inventory.md` §C).

Assign the secrecy class and the status from the measured model (`2026-10-13-probe-session-W-results.md` §4, `2026-10-13-probe-results-swing-usable.md`, feasibility doc A.2). The rule: `stub` when the read is secret in combat or always, or the function is absent on Forever; `passthrough` otherwise. Decisions already made (apply them as written):

| Name(s) | Status | Stub result and reason |
|---|---|---|
| `UnitPower`, `UnitPartialPower` | stub | `0`: resource values are secret always [W PR16] |
| `UnitPowerMax`, `UnitPowerType` | passthrough | plain (100 for rage) [W PR16] |
| `GetPowerRegenForPowerType`, `GetManaRegen` | stub | `0, 0`: secret in combat [W PR16] |
| `UnitHealth`, `UnitHealthMax`, `UnitGetTotalAbsorbs` | stub | `0`: target health secret always [W PR14]; player unprobed |
| `UnitInRange` | stub | `false, true` (inRange, checkedRange): secret always [W PR7] |
| `UnitAttackSpeed` | stub | `2, nil`: secret in combat [SU PR2] (2 so `UnitAttackSpeed("player") > 0` at load holds) |
| `UnitDamage`, `UnitAttackPower`, `UnitWeaponAttackPower`, `UnitArmor`, `UnitStat`, `GetCombatRating`, `GetCombatRatingBonus`, `GetCritChance`, `GetSpellCritChance`, `GetRangedCritChance`, `GetSpellBonusDamage`, `GetMasteryEffect`, `GetHaste`, `GetMeleeHaste`, `UnitSpellHaste` | stub | `0` (every return 0): stats family secret in combat [W PR2, PR4] |
| `GetUnitSpeed` | stub | `0, 0, 0, 0`: secret in combat [W PR14] |
| `GetTotemInfo` | stub | `false, "", 0, 0, 0`: secret in combat [W PR12] |
| `C_UnitAuras.GetBuffDataByIndex`, `GetDebuffDataByIndex`, `GetPlayerAuraBySpellID`, `GetAuraDataByAuraInstanceID` | stub | `nil`: auras secret in combat, reads error when tainted [W §4] |
| `C_UnitAuras.GetAuraSlots` | stub | `nil` (no continuation token, no slots) |
| `AuraUtil.ForEachAura`, `AuraUtil.FindAura` | stub | no-op returning nothing / `nil` |
| `AuraUtil.UnpackAuraData` | passthrough | pure Lua unpack of a table |
| `C_Spell.GetSpellCooldown` | stub | shared table `{ startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }`: times secret in combat [W PR11] |
| `C_Spell.GetSpellCharges` | stub | shared table `{ currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }` |
| `C_Spell.GetSpellCastCount` | stub | `0` |
| `C_Spell.GetSpellLossOfControlCooldown` | stub | `nil, nil`: absent on Forever |
| `UnitCastingInfo`, `UnitChannelInfo` | stub | pass the call through when `unit == "player"` (plain [W PR9]); otherwise `nil` (target casts flagged secret) |
| `CombatLogGetCurrentEventInfo` | stub | `nil`: absent on Forever; registering CLEU is forbidden |
| `UnitAura`, `UnitAuraBySlot`, `GetTalentInfoByID`, `GetPvpTalentInfoByID`, `GetSpellBaseCooldown` | stub | `nil`: absent or dead on Forever |
| `GetUnitEmpowerStageDuration`, `GetUnitEmpowerHoldAtMaxTime` | stub | `0` |
| `UnitGUID`, `UnitName`, `UnitIsUnit`, `UnitClass`, `UnitClassBase`, `UnitLevel`, `UnitExists`, `UnitCanAttack`, `UnitIsDead`, `UnitClassification`, `UnitThreatSituation`, `UnitAffectingCombat`, `UnitIsPlayer`, `UnitIsFriend`, `UnitCreatureType` | passthrough | plain in combat [W PR14; gate spike] |
| `C_Spell.IsSpellUsable`, `IsCurrentSpell`, `GetSpellPowerCost`, `C_SpellActivationOverlay.IsSpellOverlayed`, `C_Item.*`, `GetInventoryItemID`, `GetBindingKey`, `GetActionInfo`, `C_LossOfControl.*`, `C_Traits.*`, `C_SpecializationInfo.GetSpecialization`, `GetSpecializationInfo`, `GetShapeshiftForm`, `GetShapeshiftFormInfo`, `GetTime`, `InCombatLockdown`, `IsActionInRange` | passthrough | plain [W PR1, PR4, PR5, PR10, PR11, PR13, PR15, PR18] |
| Everything unprobed and present on Forever (group, instance, world, spellbook, class info, CVars, build) | passthrough | not secret-flagged; a secret result would reach Hekili only in combat and is Phase 1 work |
| Any name `wow_api_search` reports absent (candidates: `SpellIsSelfBuff`, bare `GetItemInfo`, `GetItemGem`, `GetSpellLink`, `IsUsableSpell`, `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `HasVehicleActionBar`, `HasOverrideActionBar`, `IsInJailersTower`, `C_Soulbinds.*`, `C_AzeriteItem.*`, `C_AzeriteEmpoweredItem.*`, `C_AzeriteEssence`, `C_PlayerInfo.IsPlayerInChromieTime`, `IsPlayerInTimerunningHeroicWorldTier`, `C_PvP.IsWarModeDesired`, `C_TooltipInfo.GetConduit`, `C_ClassTalents.GetActiveHeroTalentSpec`, `GetHeroTalentSpecsForClassSpec`) | stub | the neutral value its Hekili caller treats as "nothing" (read the call site: `false` for `Is*`, `nil` otherwise) |

The deprecated shims (`IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `SpellIsSelfBuff`, `IsActionInRange`, `HasVehicleActionBar`, `HasOverrideActionBar`) exist only when the CVar `loadDeprecationFallbacks` is on. Treat them as `passthrough`; the library's `missing` fallback (Task 3) covers the case where they are nil at load, and the notes file records them for Phase 3b porting to `C_SpellBook.IsSpellKnown`, `C_ActionBar.*`.

- [ ] **Step 4: Write the inventory section of `docs/forever-facade-notes.md`**

```markdown
# Forever facade notes

Working notes for Phase 2 (the VirtualGameAPI-1.0 skeleton) and the hand-off to Phases 1 and 3b.

## Inventory

Every game API name a loaded Hekili file reads, with its Forever status. `tools/api_inventory.txt` is
the machine-readable copy; `tools/list_api_reads.sh` regenerates the candidate list.

| Name | Forever | Secrecy | Status | Stub returns | Hekili call sites |
|---|---|---|---|---|---|
| `UnitPower` | present | secret always [W PR16] | stub | `0` | State.lua reset, Events.lua UNIT_POWER_FREQUENT |
| ... one row per inventory name ... |
```

Fill every row. Call sites come from `tools/list_api_reads.sh FILE` per file (file names are enough; line numbers are optional).

- [ ] **Step 5: Commit**

```bash
git add tools/list_api_reads.sh tools/api_inventory.txt docs/forever-facade-notes.md
git commit -m "docs(facade): inventory of every game API read, with Forever status and stub decisions"
git push
```

### Task 3: The VirtualGameAPI-1.0 library with headless tests

**Files:**
- Create: `Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua`
- Create: `Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.xml`
- Create: `Libs/VirtualGameAPI-1.0/README.md`
- Create: `Libs/VirtualGameAPI-1.0/LICENSE` (MIT, copyright 2026 Zack Samsel)
- Create: `Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua`
- Create: `.busted`
- Modify: `embeds.xml` (first include)

**Interfaces:**
- Produces: `local VGA = LibStub("VirtualGameAPI-1.0")`. `VGA.<Global>` and `VGA.<Namespace>.<Member>` for every inventory name. `VGA.Status(name) -> "passthrough" | "stub" | "missing" | nil`. `VGA.Why(name) -> string`. `VGA.Stubs() -> array of names` (sorted, built once at load; includes `missing`). `VGA.Inventory() -> array of all names`.
- Consumes: `tools/api_inventory.txt` (tests only).

- [ ] **Step 1: Write the failing tests**

`.busted`:
```lua
return {
    default = { ROOT = { "Libs/VirtualGameAPI-1.0/spec" }, pattern = "_spec", verbose = true },
}
```

`Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua`:
```lua
-- Headless tests for VirtualGameAPI-1.0 under a fake _G. Run from the repository root:
--   busted
local LIB = "Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua"
local INVENTORY = "tools/api_inventory.txt"

local function readInventory()
    local names = {}
    for line in io.lines(INVENTORY) do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then names[#names + 1] = line end
    end
    return names
end

-- Installs a fake function for `name` ("UnitPower" or "C_Spell.GetSpellCooldown") in _G and
-- returns the call log it appends to.
local function fake(name, calls)
    local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
    local f = function(...)
        calls[#calls + 1] = { name = name, n = select("#", ...), ... }
        return "real:" .. name
    end
    if ns then
        _G[ns] = _G[ns] or {}
        _G[ns][key] = f
    else
        _G[name] = f
    end
end

local function unfake(name)
    local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
    if ns then _G[ns][key] = nil else _G[name] = nil end
end

local function fakeLibStub()
    local libs = {}
    local LibStub = setmetatable({}, { __call = function(self, major, silent)
        return libs[major] or (not silent and error("missing " .. major)) or nil
    end })
    function LibStub:NewLibrary(major, minor)
        if libs[major] then return nil end
        libs[major] = {}
        return libs[major]
    end
    function LibStub:GetLibrary(major, silent) return self(major, silent) end
    return LibStub
end

describe("VirtualGameAPI-1.0", function()
    local names, calls, VGA

    setup(function()
        names = readInventory()
        assert.is_true(#names > 100, "inventory should list the whole read surface")
    end)

    before_each(function()
        calls = {}
        _G.LibStub = fakeLibStub()
        _G.issecretvalue = function() return false end
        for _, n in ipairs(names) do fake(n, calls) end
        VGA = assert(loadfile(LIB))()
        VGA = VGA or _G.LibStub("VirtualGameAPI-1.0")
    end)

    after_each(function()
        for _, n in ipairs(names) do unfake(n) end
        _G.LibStub = nil
        _G.issecretvalue = nil
    end)

    local function entry(name)
        local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
        if ns then return VGA[ns] and VGA[ns][key] end
        return VGA[name]
    end

    it("has a status and a function for every inventory name", function()
        for _, n in ipairs(names) do
            local s = VGA.Status(n)
            assert.is_truthy(s, n .. " has no status")
            assert.is_true(s == "passthrough" or s == "stub", n .. " status is " .. tostring(s))
            assert.is_function(entry(n), n .. " has no function")
            assert.is_string(VGA.Why(n), n .. " has no reason")
        end
    end)

    it("has no entry outside the inventory", function()
        local set = {}
        for _, n in ipairs(names) do set[n] = true end
        for _, n in ipairs(VGA.Inventory()) do
            assert.is_true(set[n] == true, n .. " is in the library but not in tools/api_inventory.txt")
        end
        assert.are.equal(#names, #VGA.Inventory())
    end)

    it("passes every passthrough call to the real function with its arguments", function()
        for _, n in ipairs(names) do
            if VGA.Status(n) == "passthrough" then
                calls = {}
                for _, m in ipairs(names) do unfake(m); fake(m, calls) end
                VGA = assert(loadfile(LIB))() or _G.LibStub("VirtualGameAPI-1.0")
                local r = entry(n)("player", 7, nil)
                assert.are.equal("real:" .. n, r, n)
                assert.are.equal(1, #calls, n .. " should call exactly once")
                assert.are.same({ name = n, n = 3, "player", 7, nil }, calls[1])
            end
        end
    end)

    it("never calls the real function from a stub", function()
        for _, n in ipairs(names) do
            if VGA.Status(n) == "stub" then
                calls = {}
                assert.has_no.errors(function() entry(n)("player", 1) end, n)
                assert.are.equal(0, #calls, n .. " stub must not call the game")
            end
        end
    end)

    it("returns the documented shapes from the critical stubs", function()
        assert.are.equal(0, VGA.UnitPower("player", 1))
        assert.are.equal(0, VGA.UnitHealth("target"))
        assert.is_nil(VGA.C_UnitAuras.GetBuffDataByIndex("player", 1))
        assert.is_nil(VGA.C_UnitAuras.GetDebuffDataByIndex("target", 1))
        assert.is_nil(VGA.C_UnitAuras.GetPlayerAuraBySpellID(1))
        local cd = VGA.C_Spell.GetSpellCooldown(61304)
        assert.are.same({ startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }, cd)
        assert.are.equal(cd, VGA.C_Spell.GetSpellCooldown(1), "stub tables are shared, not allocated per call")
        local ch = VGA.C_Spell.GetSpellCharges(1)
        assert.are.same({ currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }, ch)
        assert.is_nil(VGA.C_Spell.GetSpellLossOfControlCooldown(1))
        assert.is_nil(VGA.CombatLogGetCurrentEventInfo())
        assert.are.same({ false, "", 0, 0, 0 }, { VGA.GetTotemInfo(1) })
        assert.are.same({ 0, 0 }, { VGA.GetPowerRegenForPowerType(1) })
        assert.are.same({ 2, nil }, { VGA.UnitAttackSpeed("player") })
        assert.are.same({ 0, 0, 0, 0 }, { VGA.GetUnitSpeed("player") })
    end)

    it("passes the player's own cast info through and hides every other unit's", function()
        assert.are.equal("real:UnitCastingInfo", VGA.UnitCastingInfo("player"))
        assert.is_nil(VGA.UnitCastingInfo("target"))
        assert.are.equal("real:UnitChannelInfo", VGA.UnitChannelInfo("player"))
        assert.is_nil(VGA.UnitChannelInfo("target"))
    end)

    it("records a passthrough whose real function is absent as missing and returns nil", function()
        unfake("UnitExists")
        VGA = assert(loadfile(LIB))() or _G.LibStub("VirtualGameAPI-1.0")
        assert.are.equal("missing", VGA.Status("UnitExists"))
        assert.is_nil(VGA.UnitExists("player"))
        local listed = false
        for _, n in ipairs(VGA.Stubs()) do if n == "UnitExists" then listed = true end end
        assert.is_true(listed, "missing entries are listed by Stubs()")
    end)

    it("lists exactly the stubbed names, sorted", function()
        local stubs = VGA.Stubs()
        for i = 2, #stubs do assert.is_true(stubs[i - 1] < stubs[i], "Stubs() must be sorted") end
        local set = {}
        for _, n in ipairs(stubs) do set[n] = true end
        for _, n in ipairs(names) do
            assert.are.equal(VGA.Status(n) ~= "passthrough", set[n] == true, n)
        end
    end)

    it("does not know names outside the inventory", function()
        assert.is_nil(VGA.Status("NoSuchFunction"))
    end)
end)
```

Note: the library must `return lib` at the end of the file (for `loadfile`), in addition to LibStub registration. Each `loadfile` creates a fresh LibStub table in `before_each`, so `NewLibrary` always succeeds.

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd ~/src/hekili/.claude/worktrees/forever-cleanup && $BUSTED`
Expected: every test fails (`cannot open Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua`).

- [ ] **Step 3: Write the library**

`Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua`:
```lua
--[[
VirtualGameAPI-1.0
A facade over the World of Warcraft game API for addons running on clients that return secret values
(WoW Forever, Midnight). Each game API an addon reads is registered here with a status:

  passthrough  the real function, called through one seam (`invoke`) so caching can be added later;
  stub         a fixed, non-secret, API-shaped result, used until a virtual game state answers the read;
  missing      a passthrough whose real function does not exist on this client (returns nil).

Namespaces mirror the game: VGA.UnitPower, VGA.C_Spell.GetSpellCooldown, VGA.AuraUtil.ForEachAura.
Query the table with VGA.Status(name), VGA.Why(name), VGA.Stubs() and VGA.Inventory().

Copyright (c) 2026 Zack Samsel. MIT licence, see LICENSE.
]]

local MAJOR, MINOR = "VirtualGameAPI-1.0", 1
local lib = LibStub:NewLibrary( MAJOR, MINOR )
if not lib then return end

local _G = _G
local status, why, inventory = {}, {}, {}

-- The single seam every passthrough goes through. A per-frame cache or a secrecy check lands here.
local function invoke( real, ... )
    return real( ... )
end

local function split( name )
    local nsName, key = name:match( "^([%w_]+)%.([%w_]+)$" )
    if nsName then return nsName, key end
    return nil, name
end

local function resolve( name )
    local nsName, key = split( name )
    if nsName then
        local t = _G[ nsName ]
        return t and t[ key ]
    end
    return _G[ key ]
end

local function slot( name )
    local nsName, key = split( name )
    if nsName then
        lib[ nsName ] = lib[ nsName ] or {}
        return lib[ nsName ], key
    end
    return lib, key
end

local function nothing() return nil end

local function passthrough( name, reason )
    local real = resolve( name )
    local t, key = slot( name )
    inventory[ #inventory + 1 ] = name
    why[ name ] = reason
    if real then
        status[ name ] = "passthrough"
        t[ key ] = function( ... ) return invoke( real, ... ) end
    else
        status[ name ] = "missing"
        t[ key ] = nothing
    end
end

local function stub( name, fn, reason )
    local t, key = slot( name )
    inventory[ #inventory + 1 ] = name
    status[ name ] = "stub"
    why[ name ] = reason
    t[ key ] = fn
end

-- Shared stub results. Callers read them and never mutate them.
local function zero() return 0 end
local function zero2() return 0, 0 end
local function zero4() return 0, 0, 0, 0 end
local function isFalse() return false end

local COOLDOWN = { startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }
local CHARGES = { currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }

-- A stub that still answers for the player's own unit, where the read is plain on Forever.
local function playerOnly( name )
    local real = resolve( name )
    return function( unit, ... )
        if unit == "player" and real then return invoke( real, unit, ... ) end
        return nil
    end
end

----------------------------------------------------------------------------------------------------
-- Resources: values are secret always on Forever [W PR16]; max and type are plain.
stub( "UnitPower", zero, "resource values are secret always on Forever" )
stub( "UnitPartialPower", zero, "resource values are secret always on Forever" )
passthrough( "UnitPowerMax", "plain (100 for rage)" )
passthrough( "UnitPowerType", "plain" )
stub( "GetPowerRegenForPowerType", zero2, "regen is secret in combat" )
stub( "GetManaRegen", zero2, "regen is secret in combat" )
-- ... one line per inventory name, grouped by family, in this order:
-- health and absorbs, stats and haste, movement, totems, auras (C_UnitAuras, AuraUtil),
-- cooldowns and charges (C_Spell), casts, combat log, talents and specialization, spellbook,
-- items, units and identity, group and world, bindings and actions, client and build.
----------------------------------------------------------------------------------------------------

table.sort( inventory )
local stubs = {}
for _, name in ipairs( inventory ) do
    if status[ name ] ~= "passthrough" then stubs[ #stubs + 1 ] = name end
end

function lib.Status( name ) return status[ name ] end
function lib.Why( name ) return why[ name ] end
function lib.Stubs() return stubs end
function lib.Inventory() return inventory end

return lib
```

Write every inventory name as a `passthrough(...)` or `stub(...)` line following the Task 2 table. Each stub line's reason string says why (the secrecy class or "absent on Forever") and the comment above the family says the shape. `UnitCastingInfo` and `UnitChannelInfo` use `stub( "UnitCastingInfo", playerOnly( "UnitCastingInfo" ), "plain for the player only [W PR9]" )`.

`Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.xml`:
```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
	<Script file="VirtualGameAPI-1.0.lua"/>
</Ui>
```

`embeds.xml`: insert `<Include file="Libs\VirtualGameAPI-1.0\VirtualGameAPI-1.0.xml"/>` as the first line after `LibStub.lua` (LibStub must load first; the library needs it).

`Libs/VirtualGameAPI-1.0/README.md`: what the library is (two paragraphs), the three statuses, the query API, how to add an entry, how to run the tests (`busted` from the addon root), and a section "Out of scope for now" stating that events (`RegisterEvent` diversion, a virtual combat log, `UNIT_AURA` payloads) are Phase 1 and Phase 3b work, and that caching is a later addition at the `invoke` seam.

`Libs/VirtualGameAPI-1.0/LICENSE`: the MIT licence text with `Copyright (c) 2026 Zack Samsel`.

- [ ] **Step 4: Run the tests until they pass**

Run: `$BUSTED`
Expected: all 9 tests pass.

- [ ] **Step 5: Lint**

Run: `$LUACHECK Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua --no-config --std lua51 --globals LibStub` (the main config excludes `Libs/`; lint the library explicitly) and `wow_lua_lint` on the file (flavor `forever`) and `wow_xml_validate` on the XML.
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add Libs/VirtualGameAPI-1.0 .busted embeds.xml
git commit -m "feat(facade): VirtualGameAPI-1.0 skeleton: passthroughs, stubs, status queries, headless tests"
git push
```

### Task 4: Redirect the small files (Hekili, Utils, Constants, Formatting, MultilineEditor, UI/PopupSlider)

**Files:**
- Modify: `Hekili.lua`, `Utils.lua`, `Constants.lua`, `Formatting.lua`, `MultilineEditor.lua`, `UI/PopupSlider.lua`

**Interfaces:**
- Consumes: `LibStub("VirtualGameAPI-1.0")` from Task 3; `tools/list_api_reads.sh FILE` from Task 2.

- [ ] **Step 1: List each file's reads**

Run: `for f in Hekili.lua Utils.lua Constants.lua Formatting.lua MultilineEditor.lua UI/PopupSlider.lua; do echo "== $f"; tools/list_api_reads.sh $f | grep -xFf tools/api_inventory.txt; done`
Expected: the inventory names each file reads (`Hekili.lua`: `C_AddOns.*`, `C_UnitAuras.*`, `AuraUtil.*`, `GetBuildInfo`, ...; `Constants.lua`: `C_SpecializationInfo.*`, `GetNumClasses`, `GetClassInfo`, `GetSpecializationInfoByID`, ...).

- [ ] **Step 2: Insert the redirection block**

Immediately after the line `local addon, ns = ...` (or the file's equivalent first line that unpacks `...`; `UI/PopupSlider.lua` and `Formatting.lua` may have none, then insert at line 1 after the header comment) add:

```lua
local VGA = LibStub( "VirtualGameAPI-1.0" )
local C_AddOns, C_UnitAuras, AuraUtil = VGA.C_AddOns, VGA.C_UnitAuras, VGA.AuraUtil
local GetBuildInfo = VGA.GetBuildInfo
```

One `local` per namespace the file uses (`C_Spell`, `C_Item`, `C_UnitAuras`, `C_SpecializationInfo`, `C_SpellBook`, `C_Traits`, `C_ClassTalents`, `C_AddOns`, `C_Texture`, `C_TooltipInfo`, `AuraUtil`, ...) and one per bare global the file uses. Existing capture lines below (`local GetBuffDataByIndex = C_UnitAuras.GetBuffDataByIndex`) now resolve through the local namespace table and stay as they are. A file that reads nothing from the inventory gets no block.

Special case in `Hekili.lua`: line 5 (`Hekili = LibStub("AceAddon-3.0"):NewAddon(...)`) and line 6 (`C_AddOns.GetAddOnMetadata`) come before any local; put the VGA block between line 4 and line 5.

- [ ] **Step 3: Verify**

Run:
```bash
for f in Hekili.lua Utils.lua Constants.lua Formatting.lua MultilineEditor.lua UI/PopupSlider.lua; do luac5.1 -p $f || echo "COMPILE FAIL $f"; done
$LUACHECK Hekili.lua Utils.lua Constants.lua Formatting.lua MultilineEditor.lua UI/PopupSlider.lua
```
Expected: compiles; luacheck reports 0 warnings on these files (no W113 left: every game read is now a local).
Then `wow_lua_lint` (flavor `forever`, `knownGlobals: ["Hekili","LibStub","ns"]`) on each file: no errors.

- [ ] **Step 4: Commit**

```bash
git add Hekili.lua Utils.lua Constants.lua Formatting.lua MultilineEditor.lua UI/PopupSlider.lua
git commit -m "refactor(facade): route Hekili, Utils, Constants, Formatting, editor reads through VirtualGameAPI"
git push
```

### Task 5: Redirect State.lua

**Files:**
- Modify: `State.lua:1-60` (file top), `State.lua:780` (`_G.UnitIsUnit`)

- [ ] **Step 1: List the reads**

Run: `tools/list_api_reads.sh State.lua | grep -xFf tools/api_inventory.txt`
Expected: about 55 names (`UnitExists`, `UnitGUID`, `UnitHealth`, `GetTotemInfo`, `C_Spell.*`, `C_Item.*`, `C_UnitAuras.*`, `C_SpellBook.*`, `UnitAura`, `UnitAuraBySlot`, `GetStablePetInfo`, ...).

- [ ] **Step 2: Insert the block after `local addon, ns = ...`**

```lua
local VGA = LibStub( "VirtualGameAPI-1.0" )
local C_Spell, C_Item, C_UnitAuras, C_SpellBook, C_SpecializationInfo, C_LossOfControl, AuraUtil =
    VGA.C_Spell, VGA.C_Item, VGA.C_UnitAuras, VGA.C_SpellBook, VGA.C_SpecializationInfo, VGA.C_LossOfControl, VGA.AuraUtil
local UnitExists, UnitGUID, UnitIsUnit, UnitCanAttack = VGA.UnitExists, VGA.UnitGUID, VGA.UnitIsUnit, VGA.UnitCanAttack
-- ... every bare name from step 1, a few per line ...
```

Change `State.lua:780` `local UnitIsUnit = _G.UnitIsUnit` to `local UnitIsUnit = VGA.UnitIsUnit`. Leave `State.lua:5882` `local UnitAuraBySlot = UnitAuraBySlot` (it now reads the file-top local).

- [ ] **Step 3: Compile**

Run: `luac5.1 -p State.lua`
Expected: OK. If it reports `too many upvalues` or `too many local variables`: find the function (the message names the line) and, for that function only, delete the file-top locals it needs least and reference them as `VGA.Name(` at its call sites, noting the change in the commit message. Re-run until it compiles.

- [ ] **Step 4: Lint**

Run: `$LUACHECK State.lua` and `wow_lua_lint` on `State.lua`.
Expected: 0 warnings, no lint errors. Check also that no secrecy-zone body changed: `git diff --stat State.lua` shows only the file-top block and line 780.

- [ ] **Step 5: Commit**

```bash
git add State.lua
git commit -m "refactor(facade): route State.lua reads through VirtualGameAPI"
git push
```

### Task 6: Redirect Events.lua

**Files:**
- Modify: `Events.lua:1-45` (file top)

Same procedure as Task 5 (list, insert block, `luac5.1 -p`, luacheck 0 warnings, `wow_lua_lint`). Points specific to this file:
- The local wrapper `local GetSpellCooldown = function(spellID) local spellCooldownInfo = C_Spell.GetSpellCooldown(spellID) ...` at `:27` stays; it reads the local `C_Spell`.
- `Events.lua:537` `local AE = C_AzeriteEssence` reads a namespace; add `local C_AzeriteEssence = VGA.C_AzeriteEssence` and make sure the inventory lists the member(s) it uses (`tools/list_api_reads.sh` prints `C_AzeriteEssence.X`); if the file only tests `if AE then`, register `C_AzeriteEssence` members anyway from the lines below `:537`.
- `Events.lua:1504` `local ForEachAura = AuraUtil.ForEachAura` reads the local `AuraUtil`.
- `Events.lua:1172` `SecureCmdOptionParse` and `:2016` `CombatLogGetCurrentEventInfo` become locals.
- The CLEU handler body (`:1709-2016`) and the `UNIT_POWER_FREQUENT` / `UNIT_AURA` handlers are not edited.

Commit: `refactor(facade): route Events.lua reads through VirtualGameAPI`.

### Task 7: Redirect Classes.lua and Targets.lua

**Files:**
- Modify: `Classes.lua:1-35`, `Targets.lua:1-30` and `Targets.lua:287, 327` (`C_PlayerInfo.*` captures inside functions read the file-top `C_PlayerInfo` local; no edit needed there).

Same procedure. Points:
- `Classes.lua:2882` `UnitClassBase( "player" )` runs at load: `UnitClassBase` must be a passthrough (plain).
- `Targets.lua:315` `C_PvP.IsWarModeDesired()`: add `local C_PvP = VGA.C_PvP`.
- Spec detection (`Classes.lua:4091-4378`) and `Targets.lua` combat-log and time-to-die bodies are not edited.

Commit: `refactor(facade): route Classes.lua and Targets.lua reads through VirtualGameAPI`.

### Task 8: Redirect UI.lua, Scripts.lua, Core.lua

**Files:**
- Modify: `UI.lua:1-45`, `Scripts.lua:1-25`, `Core.lua:1-30`

Same procedure. Points:
- `UI.lua:43` captures `C_PetBattles.IsInBattle` at load: with `local C_PetBattles = VGA.C_PetBattles` above it, a `missing` entry yields the `nothing` function, so the capture is a function and `:976` never calls nil.
- The `GetSpellCooldown` wrapper at `UI.lua:30` reads the local `C_Spell`. The cooldown arithmetic at `:1495-1516` and `:1700-1746` is not edited.
- `Core.lua` reads few names (`GetTime`, `InCombatLockdown`, `UnitClass`, ...); the block is short.

Commit: `refactor(facade): route UI, Scripts and Core reads through VirtualGameAPI`.

### Task 9: Redirect Options/Options.lua, Options/ChatCommands.lua, Options/DevTools.lua

**Files:**
- Modify: `Options/Options.lua:1-45`, `Options/ChatCommands.lua:1-20`, `Options/DevTools.lua:1-70`

Same procedure. Points:
- `Options/Options.lua:34` `C_ClassColor.GetClassColor( class.file )` runs at load: `local C_ClassColor = VGA.C_ClassColor` above it.
- `Options/DevTools.lua:22-25` `C_Spell.IsSpellPassive or _G.IsPassiveSpell`: keep the `or` fallbacks but read `_G.IsPassiveSpell` as is (it is a deprecated bare global not in the inventory; `tools/list_api_reads.sh` lists `_G.` reads, so add `IsPassiveSpell`, `IsHarmfulSpell`, `IsHelpfulSpell`, `IsPressHoldReleaseSpell` to the inventory as passthroughs and use `VGA.IsPassiveSpell` instead of `_G.IsPassiveSpell`). Update `tools/api_inventory.txt`, the library and the notes table in the same commit; `$BUSTED` must still pass.
- Strings such as `self:Append( "local GetSpellCastCount = C_Spell.GetSpellCastCount" )` are generated code, not reads; leave them.

Commit: `refactor(facade): route Options reads through VirtualGameAPI`.

### Task 10: The read checker, the first facade notes, Checkpoint A

**Files:**
- Create: `tools/check_api_reads.sh`
- Modify: `docs/forever-facade-notes.md` (add sections "Secrecy zone", "Stub call sites that would throw", "Edits no facade absorbs")

- [ ] **Step 1: Write `tools/check_api_reads.sh`**

```bash
#!/usr/bin/env bash
# Fails when a file loaded by Hekili.toc reads a game API from tools/api_inventory.txt directly
# instead of through LibStub("VirtualGameAPI-1.0"). Bare reads come from luacheck (which ignores
# strings and comments); namespace members and _G reads come from grep.
set -uo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
globals=$(sed -E 's/\..*//' tools/api_inventory.txt | sort -u | paste -sd'|')
members=$(grep '\.' tools/api_inventory.txt | sed 's/\./\\./' | paste -sd'|')
fail=0
hits=$("$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}" 2>/dev/null \
    | grep -E "accessing undefined variable '($globals)'")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -nE "(^|[^.:A-Za-z0-9_])($members)\b" "${files[@]}" | grep -vE '^[^:]+:[0-9]+:\s*--')
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -nE "_G(\.|\[\"')($globals)\b" "${files[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: no direct game API read in ${#files[@]} loaded files"
exit $fail
```

Note: the member grep catches `C_Spell.GetSpellCooldown(` even when `C_Spell` is the VGA local, because the local *is* the redirection; that check therefore only matters when `C_Spell` is NOT declared as a local in that file. Make the second check precise: for each file, skip a namespace member hit when the file contains `local .*\bC_Spell\b.*= .*VGA\.C_Spell` (a one-line awk or a loop per namespace). Keep the script under 40 lines.

- [ ] **Step 2: Run it and the whole verification set**

Run: `tools/check_api_reads.sh && $LUACHECK . && $BUSTED`
Expected: `ok: ...`, luacheck `0 warnings / 0 errors`, tests pass. Then `wow_lua_lint` on every loaded root file (16 files): no errors.

- [ ] **Step 3: Write the notes sections**

Append to `docs/forever-facade-notes.md`:

```markdown
## Secrecy zone (bodies unchanged in Phase 2; Phase 3b revisits them)

| Code | Where | What it reads through the facade |
|---|---|---|
| cooldown metatable | `State.lua` `mt_default_cooldown` (search `local mt_default_cooldown`) | `C_Spell.GetSpellCooldown`, `GetSpellCharges`, `GetSpellLossOfControlCooldown` |
| `ScrapeUnitAuras` | `State.lua` (search `function ns.ScrapeUnitAuras` or `local function ScrapeUnitAuras`) | `C_UnitAuras.Get{Buff,Debuff}DataByIndex`, `UnitIsUnit` |
| `state.reset` | `State.lua` (search `function state.reset`) | `UnitPower`, `UnitPowerMax`, regen, health, `UnitAttackSpeed`, `GetTotemInfo`, `UnitCastingInfo` |
| `UNIT_POWER_FREQUENT` handler | `Events.lua` | `UnitPower` |
| `UNIT_AURA` handler | `Events.lua` | `AuraUtil.ForEachAura`, `C_UnitAuras.GetAuraDataByAuraInstanceID` |
| combat-log handler | `Events.lua` `CLEU_HANDLER` and the registration | `CombatLogGetCurrentEventInfo`, `UnitAttackSpeed` |
| target counting, time to die | `Targets.lua` | `UnitHealth`, `UnitHealthMax`, `UnitGUID`, `GetUnitSpeed` |
| UI cooldown arithmetic | `UI.lua` `OnUpdate` and `RefreshCooldowns` | `C_Spell.GetSpellCooldown`, `UnitCastingInfo` |
| spec detection | `Classes.lua` `SpecializationChanged` | `C_SpecializationInfo.*` |

## Stub call sites that would throw or misbehave (for Phase 3b; not patched here)

| Stub | Call site | Effect |
|---|---|---|
| `UnitHealth` -> 0 | `Targets.lua` enemy scan `UnitHealth( unit ) > 1` | every plate filtered out (comparison is fine, result is wrong) |
| ... |

## Edits no facade absorbs (feasibility doc C.5)

GCD spell 61304 -> 29515 (`Classes.lua`, `UI.lua`, `Events.lua`); the enemy-scan health comparison; TTD;
spec identity (pseudo-spec 1491); talents (`C_Traits` walk); CLEU registration removal/diversion; version gates
(`Hekili.lua`, `Core.lua`); division by zero audit; load-time nils.
```

Fill the "would throw" table by reading each stub's call sites (from the inventory table's call-site column): a division by the result, a nil index, a `#` on nil, an arithmetic on nil. List at least: `UnitAttackSpeed` sites, `GetPowerRegenForPowerType` in `forecastResources`, `C_UnitAuras.GetAuraSlots` consumers, `GetTotemInfo` consumers, `UnitCastingInfo("target")` consumers, `CombatLogGetCurrentEventInfo` at the registration (nil tuple into `CLEU_HANDLER`).

- [ ] **Step 4: Commit**

```bash
chmod +x tools/check_api_reads.sh
git add tools/check_api_reads.sh docs/forever-facade-notes.md
git commit -m "tools(facade): checker that fails on any direct game API read; facade notes for Phase 3b"
git push
```

- [ ] **Step 5: Checkpoint A (the orchestrator, not a subagent)**

Point the client's checkout at the branch: `git -C ~/src/hekili checkout --detach forever-cleanup` (the main checkout is clean on `forever`; detaching keeps the branch checked out only in the worktree). Ask the user to log in or `/reload` on Forever and paste any Lua errors. Goal: no errors at login and on `/reload`. Checkpoint A runs after Task 19 (see "Execution order"), so the checkout has its libraries and the TOC says 16001. It means "loads with the libraries and the facade; retail content still present".

---

## Part 2: the cleanup

### Task 11: Archive the expansion folders

**Files:**
- Move: `TheWarWithin/`, `Dragonflight/`, `Shadowlands/`, `BfA/`, `Legion/`, `Wrath/`, `Cataclysm/`, `TheBurningCrusade/` -> `archive/<same name>/`
- Create: `archive/README.md`, `Forever/README.md`
- Modify: `Hekili.toc` (remove every line under those folders), `.luacheckrc` (replace the expansion exclusions with `archive/`)

- [ ] **Step 1: Move with history**

```bash
mkdir -p archive Forever
for d in TheWarWithin Dragonflight Shadowlands BfA Legion Wrath Cataclysm TheBurningCrusade; do git mv "$d" "archive/$d"; done
```

- [ ] **Step 2: READMEs**

`archive/README.md`:
```markdown
# Archived retail content

Reference material kept temporarily: the retail (The War Within 11.2) class modules, expansion item and system
files and SimulationCraft priority lists, moved here unchanged by `git mv` so history follows them. Nothing in
this folder is loaded: no file is listed in `Hekili.toc` or any XML include, and lint skips it. It exists so the
retail spec modules of the nine Forever classes and their APLs can be read for ability shapes and APL ideas while
the Forever class files are written. It will be removed once those files exist.
```

`Forever/README.md`:
```markdown
Forever class files arrive in Phase 3b (Warrior first).
```

- [ ] **Step 3: TOC and lint config**

Delete from `Hekili.toc` every line starting with `TheBurningCrusade\`, `Wrath\`, `Cataclysm\`, `Legion\`, `BfA\`, `Shadowlands\`, `Dragonflight\`, `TheWarWithin\`. In `.luacheckrc` `exclude_files`, remove the eight expansion entries (`archive/` is already there).

- [ ] **Step 4: Verify nothing loads from the archive**

Run:
```bash
grep -nE "TheWarWithin|Dragonflight|Shadowlands|BfA|Legion|Wrath|Cataclysm|TheBurningCrusade|archive" Hekili.toc embeds.xml Bindings.xml UI/*.xml; echo "exit $?"
$LUACHECK . && tools/check_api_reads.sh
```
Expected: the grep prints nothing (exit 1); lint and the checker pass. Then `wow_toc_validate` on `Hekili.toc`: no "listed but missing" file.

- [ ] **Step 5: Functions the engine still calls that lived in archived files**

Run: `grep -ohE "^\s*(function )?ns\.[A-Za-z_]+|^ns\.[A-Za-z_]+\s*=" archive -r | sed -E 's/.*ns\.([A-Za-z_]+).*/\1/' | sort -u > /tmp/archived_ns.txt; for n in $(cat /tmp/archived_ns.txt); do grep -nE "\bns\.$n\b" *.lua Options/*.lua | grep -v "^archive" ; done`
Expected: a short list (for example `ns.updateTalents` override from `Dragonflight/Classes.lua`, which also exists in `Events.lua`). Record every hit in the Task 12 to 18 scopes below (the removal tasks delete the callers); nothing is edited in this task.

- [ ] **Step 6: Commit**

```bash
git add -A archive Forever Hekili.toc .luacheckrc
git commit -m "chore(archive): move the expansion and retail class folders to archive/ unloaded, history kept"
git push
```

### Task 12: Events.lua: azerite, essence and retail-only handlers

**Files:**
- Modify: `Events.lua` (azerite and essence handlers around `:483-641`, `ns.updatePowers`, `ns.updateEssences`, the `C_AzeriteEssence` block at `:537`, the commented-out azerite loop around `:1033-1058`, the Timerunning check at `:1738-1741`, PvP talents in `ns.updateTalents` `:440-460`, arena prep at `:392`, `IsInJailersTower` at `:341, 387`)
- Modify: `tools/api_inventory.txt`, `Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua`, `docs/forever-facade-notes.md` (drop the names no longer read: `C_AzeriteEmpoweredItem.*`, `C_AzeriteItem.*`, `C_AzeriteEssence.*`, `GetPvpTalentInfoByID`, `C_SpecializationInfo.GetPvpTalentSlotInfo`, `IsInJailersTower` if unused elsewhere)

- [ ] **Step 1: Find each block by content** (`grep -n "Azerite\|Essence\|essence\|azerite\|Timerunning\|pvptalent\|PvpTalent\|JailersTower\|torghast\|ARENA_PREP" Events.lua`), delete the handlers, the helper functions and their `RegisterEvent` lines. Keep `ns.updateTalents` itself (Phase 3b rewrites it) but delete its PvP-talent half. Where a deleted function was called from another file (`grep -n "updatePowers\|updateEssences\|state.torghast" *.lua Options/*.lua`), delete the caller lines too and list them in the commit message.
- [ ] **Step 2: Trim the inventory**: run `tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt` and remove from `tools/api_inventory.txt`, the library and the notes table every name that no loaded file reads any more. `$BUSTED` must pass (the reverse-coverage test enforces this).
- [ ] **Step 3: Verify**: `luac5.1 -p Events.lua && $LUACHECK Events.lua && tools/check_api_reads.sh && $BUSTED`, `wow_lua_lint Events.lua`. `git diff Events.lua` must not touch the `UNIT_POWER_FREQUENT`, `UNIT_AURA` or `CLEU_HANDLER` bodies.
- [ ] **Step 4: Commit** `refactor(events): remove azerite, essence, PvP-talent, Torghast and Timerunning handlers`.

### Task 13: State.lua: retail systems

**Files:**
- Modify: `State.lua`: azerite and legendary metatables (around `:4474-4554`; search `azerite`, `essence`, `legendary`, `runeforge`), `state.empowerment` and empower paths (search `empower`), `hero_tree` (search `hero_tree`, `:140` and the set-bonus matching around `:4989-5027`), `pvptalent` (search `pvptalent`), the trinket stat-stick tables (around `:412-720`; keep `trinket.t1/t2` cooldown and ready, delete the stat-proc zoo), `cyclotronic_blast` and BfA/SL trinket blocks in `state.reset` (around `:6960-7035`: these are inside `state.reset` but are retail trinket content, not secrecy-zone reads; delete only those blocks and say so in the commit), the commented-out `--[[ ]]` blocks (about 277 lines), `state.torghast`, `IsInJailersTower` at `:6086`.
- Modify: `ns.attr` list at the end of the file: remove the deleted attribute names.
- Modify: inventory, library and notes for names no longer read.

Same verification as Task 12 plus: `grep -n "azerite\|essence\|legendary\|runeforge\|hero_tree\|pvptalent\|empower\|torghast" State.lua` prints nothing. The `mt_default_cooldown`, `ScrapeUnitAuras` and `state.reset` resource, health, swing and cast bodies are unchanged (`git diff` review).

Commit: `refactor(state): remove azerite, legendary, empower, hero tree, PvP talent and retail trinket systems`.

### Task 14: Constants.lua: hero trees and retail specializations

**Files:**
- Modify: `Constants.lua`: `ns.HeroTrees` and `getActiveHeroTreeName` (around `:310-552`), the `ns.Specializations` table (around `:103-300`; keep the 9 Forever classes' entries and the class-level helpers `ns.getSpecializationKey`, `ns.getSpecializationID`; delete Death Knight, Demon Hunter, Monk, Evoker rows), `SkeletonTalentEnhancements` if retail-only (around `:697+`).
- Check callers: `grep -n "HeroTrees\|getActiveHeroTreeName\|SkeletonTalentEnhancements" *.lua Options/*.lua` and delete the callers (Options spec panels show hero tree names; delete those lines).

Verification as Task 12. Commit: `refactor(constants): drop hero trees and the retail-only class rows`.

### Task 15: Classes.lua: shared retail content

**Files:**
- Modify: `Classes.lua`: PvP trinkets (medallion, badge, emblem, insignia; around `:3439-3706`), corrupted on-use items (`:3707-3785`), holiday items (`:3786-3910`), Dragonflight and TWW potions (`:2685-2884`; keep the `potion` framework ability and the `all:RegisterAuras` entries the engine needs: `casting`, `movement`, the `bloodlust` family, `potion`, `use_items`), M+ affix and SL season auras in the shared aura block (`:1472-2724`), `heart_essence` (`:3407`), retail-only racials (keep Human, Dwarf, Night Elf, Gnome, Orc, Undead, Tauren, Troll; delete the rest), retail group buffs.
- Keep: the registration API, the `all` spec, `SpecializationChanged`, `class.spellFilters` mechanism.

Verification as Task 12 plus `grep -n "medallion\|corrupt\|heart_essence\|dragonflight\|tww_\|M+\|affix" Classes.lua` prints nothing relevant. Commit: `refactor(classes): remove PvP trinkets, retail potions, affixes, holiday items and non-vanilla racials`.

### Task 16: Utils.lua: covenants and loadout export

**Files:**
- Modify: `Utils.lua`: covenant cache (`:779-870`; `ns.WipeCovenantCache`, `ns.IsDisabledCovenant`, `ns.AreCovenantsDisabled`, `C_TooltipInfo.GetConduit`), loadout export (`:948-1092`; `C_Traits`, `C_ClassTalents`, `ExportUtil`, `ClassTalentImportExportMixin`).
- Callers: `grep -n "WipeCovenantCache\|IsDisabledCovenant\|AreCovenantsDisabled\|IsDisabledCovenantSpell\|GetLoadoutExport\|loadout" *.lua Options/*.lua`; delete the callers (`State.lua:34`, `State.lua` `IsKnown` covenant branch, `Events.lua:38`, `Classes.lua:4404`, the Options button that shows the export string).

Verification as Task 12. Commit: `refactor(utils): remove the covenant cache and the talent loadout export`.

### Task 17: UI.lua: empowerment and SpellFlash

**Files:**
- Modify: `UI.lua`: empowerment stage glow and `empower_to` rendering (search `empower`); Masque stays optional (`LibStub("Masque", true)`); the SpellFlash code stays (library policy).
- Modify: `Core.lua`: `empower_to` writes if any (search `empower`).

Verification as Task 12; the cooldown arithmetic at `OnUpdate` and `RefreshCooldowns` is unchanged. Commit: `refactor(ui): remove empowerment rendering; Masque stays optional`.

### Task 18: Options and dropped libraries

**Files:**
- Delete: `Options/Archive.lua`
- Modify: `Options/Options.lua`: `oneTimeFixes` (`:44-126`, replace with an empty table and keep the loop), essence, covenant and soulbind toggles and panels (search `essence`, `covenant`, `soulbind`, `C_Soulbinds`), the Wago/Discord/patron text if it points at retail services (keep the help URLs that still make sense); the `SFX-Info-URL` widgets stay (the pack is vendored). Library call sites stay (library policy).
- Modify: `Core.lua:64-67` LibDualSpec: keep (vendored in Task 19).
- Modify: `Hekili.toc` `OptionalDeps`: drop `AddOnSkins, ButtonForge` only if unreferenced (`grep -n "AddOnSkins\|ButtonForge" *.lua Options/*.lua`).

Verification as Task 12. Commit: `refactor(options): drop Archive.lua, one-time fixes and the retail panels`.

### Task 19: TOC, vendored libraries, embeds

**Files:**
- Modify: `Hekili.toc` (`## Interface: 16001`; remove `## X-Curse-Project-ID`, `## X-WoWI-ID`, `## X-Wago-ID`; `## Version: forever-dev`)
- Modify: `embeds.xml` (same includes as today, in the same order, plus the VirtualGameAPI include already added in Task 3; fix any path whose vendored layout differs)
- Modify: `.pkgmeta` (remove every external now vendored; keep `package-as` and `enable-nolib-creation: no`)
- Delete: `.travis.yml`, `.github/workflows/` retail release workflows (keep `.github/ISSUE_TEMPLATE` and `FUNDING.yml`)
- Create: `Libs/CREDITS.md`
- Vendor into `Libs/` every library `embeds.xml` includes: `LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceGUI-3.0`, `AceConsole-3.0`, `AceConfig-3.0`, `AceTimer-3.0`, `AceSerializer-3.0`, `AceComm-3.0` (with its ChatThrottleLib), `AceEvent-3.0`, `AceDB-3.0`, `AceDBOptions-3.0` (all from Ace3 `Release-r1403`), `LibSharedMedia-3.0`, `AceGUI-3.0-SharedMediaWidgets`, `AceGUI-3.0_SFX-Widgets`, `LibSpellRange-1.0`, `LibRangeCheck-3.0`, `LibCompress`, `LibDeflate`, `LibDataBroker-1.1`, `LibDBIcon-1.0`, `LibDualSpec-1.0`, `LibCustomGlow-1.0`, `LibChatAnims`, `LibTranslit-1.0`. `SpellFlashCore` is already in `Libs/` and stays.

Library policy: vendor everything; drop nothing in this task. Record in `Libs/CREDITS.md` which libraries declare Forever support upstream and which do not, and any load gate found in step 2, so Checkpoint B can tell a library failure from a Hekili one.

- [ ] **Step 1: Fetch** (into `$CLAUDE_JOB_DIR/tmp/libs/`, then copy only the needed folders):

```bash
T=/home/zack/.claude/jobs/9fe9990a/tmp/libs; mkdir -p $T && cd $T
git clone --depth 1 --branch Release-r1403 https://github.com/WoWUIDev/Ace3 Ace3
git clone --depth 1 https://github.com/WeakAuras/LibRangeCheck-3.0 LibRangeCheck-3.0
git clone --depth 1 https://github.com/AdiAddons/LibDualSpec-1.0 LibDualSpec-1.0
git clone --depth 1 https://github.com/SafeteeWoW/LibDeflate LibDeflate
git clone --depth 1 https://github.com/Stanzilla/LibCustomGlow LibCustomGlow
git clone --depth 1 https://github.com/tekkub/libdatabroker-1-1 LibDataBroker-1.1
git clone --depth 1 https://github.com/SFX-WoW/AceGUI-3.0_SFX-Widgets AceGUI-3.0_SFX-Widgets
git clone --depth 1 https://github.com/ascott18/LibSpellRange-1.0 LibSpellRange-1.0
git clone --depth 1 https://github.com/Vardex/LibTranslit LibTranslit-1.0
# wowace SVN repositories serve files over plain HTTPS (directory listings are HTML):
for r in "libsharedmedia-3-0/trunk/LibSharedMedia-3.0" "libdbicon-1-0/trunk/LibDBIcon-1.0" "ace-gui-3-0-shared-media-widgets/trunk/AceGUI-3.0-SharedMediaWidgets" "libcompress/trunk" "libchatanims/trunk/LibChatAnims"; do
    wget -q -r -np -nH -R "index.html*" "https://repos.wowace.com/wow/$r/"
done
```
Check each mirrored folder is complete (`lib.xml`/`widget.xml` and every file they reference exist). For each library record the tag or commit (`git rev-parse HEAD`) or, for wowace, the `$Id`/`MINOR` revision in the main file's header. Copy each library folder into `Libs/<Name>/` matching the paths `embeds.xml` uses, with its licence file (`LICENSE`, `LICENSE.txt`, or `Libs/<Name>/LICENSE-NOTE.md` quoting the header when there is no file). Do not copy `.git`, tests or `.pkgmeta` files. Keep `Libs/SpellFlashCore/` as it is.

- [ ] **Step 2: Note the load gates**: `grep -rln "Interface\|WOW_PROJECT\|GetBuildInfo\|16001\|Forever" Libs/*/` and read each hit. Record per library in `Libs/CREDITS.md`: declares Forever support (yes/no, with the commit or TOC line), and any early return keyed on build or project (`SpellFlashCore` returns for builds below 110000; note it). Do not drop anything.

- [ ] **Step 3: `embeds.xml`**: keep today's include list and order (with the VirtualGameAPI include second, after LibStub). Verify every `file=` path exists exactly (`for p in $(grep -oE 'file="[^"]+"' embeds.xml | sed 's/file="//; s/"//; s/\\/\//g'); do [ -f "$p" ] || echo "MISSING $p"; done`); LibRangeCheck's main file may sit in a subfolder (see `.pkgmeta` `move-folders`): move it so `Libs\LibRangeCheck-3.0\LibRangeCheck-3.0.lua` exists. AceGUI loads before AceConfig and the widget packs.

- [ ] **Step 4: `Libs/CREDITS.md`**: a table: library, upstream URL, pinned tag or commit, licence, author credit, Forever support upstream, load gate. Include VirtualGameAPI-1.0 (this repository, MIT) and the notes that LibDataBroker-1.1 and LibSpellRange-1.0 have no licence file and that LibCompress is GPL v2.

- [ ] **Step 5: Verify**: `wow_toc_validate` on `Hekili.toc` (interface 16001 accepted, no missing files), `wow_xml_validate` on `embeds.xml`, `Bindings.xml`, `UI/PopupSlider.xml` and every vendored `.xml` listed in `embeds.xml`; the path loop above prints nothing; `$LUACHECK .` (Libs excluded) and `tools/check_api_reads.sh` pass.

- [ ] **Step 6: Commit**: `build: TOC 16001, every embedded library vendored and pinned in Libs/CREDITS.md` and push. One commit is fine.

### Task 20: LuaLS, the final sweep, Checkpoint B

**Files:**
- Create: `.luarc.json`
- Modify: whatever the sweep finds (small fixes only; anything larger becomes a note in `docs/forever-cleanup.md`)

- [ ] **Step 1: `.luarc.json`**
```json
{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime.version": "Lua 5.1",
  "workspace.library": ["/home/zack/.local/share/vscode-wow-api/Annotations/Core"],
  "workspace.ignoreDir": ["Libs", "archive", ".claude", ".git"],
  "workspace.checkThirdParty": false,
  "diagnostics.globals": ["LibStub", "Hekili", "ns"],
  "diagnostics.disable": ["lowercase-global", "undefined-field", "need-check-nil", "cast-local-type", "assign-type-mismatch", "param-type-mismatch", "redundant-parameter", "missing-parameter", "inject-field", "duplicate-set-field", "undefined-global"]
}
```
Run: `lua-language-server --check . --checklevel=Error --logpath=/home/zack/.claude/jobs/9fe9990a/tmp/luals`
Expected: `Diagnosis completed, no problems found` at the Error level. Fix real errors (syntax, a global read of a deleted name); add a disable only for a category that is pure legacy style, and say which in the commit message.

- [ ] **Step 2: Dangling-reference sweep**
```bash
git grep -nE 'Azerite|Essence|Covenant|Soulbind|Conduit|Legendary|HeroTree|hero_tree|Timerunning|torghast|Evoker|DEATHKNIGHT|DEMONHUNTER|MONK|empower' -- '*.lua' ':!archive' ':!Libs' ':!docs'
```
Expected: nothing, or only comments and the `all` aura names the engine still needs (list any remaining hit in `docs/forever-cleanup.md` with the reason it stays). Then `tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | diff - tools/api_inventory.txt` must be empty (the inventory equals what is read), `$BUSTED`, `$LUACHECK .`, `tools/check_api_reads.sh`, `wow_lua_lint` on all 16 loaded root files, `wow_toc_validate`, `wc -l` of the loaded Lua (expected about 37k).

- [ ] **Step 3: Commit** `chore(lint): LuaLS config and the post-cleanup sweep`, push.

- [ ] **Step 4: Checkpoint B (orchestrator)**: `git -C ~/src/hekili checkout --detach forever-cleanup`; ask the user to `/reload`, confirm no errors, and `/hekili` opens the options window. Fix what the user reports (each fix its own commit), then repeat.

### Task 21: `docs/forever-cleanup.md`

**Files:**
- Create: `docs/forever-cleanup.md`
- Modify: `docs/forever-facade-notes.md` (final counts)

Content, in this order:
1. **Facade status table**: counts of passthrough, stub and missing (from `VGA.Stubs()` and the inventory file: `grep -c "^passthrough\|^stub"` of the library), the full stub list with the shape each returns.
2. **Archived and removed**: per area (expansion folders, Classes, State, Constants, Events, UI, Utils, Options, libraries), lines before and after (`git show forever:FILE | wc -l` against `wc -l FILE`), with the commit hash.
3. **Kept but flagged for Phase 3b**: the secrecy zone list, the C.5 edits, the stub call sites that would throw (pointer to the notes file plus the table copied in).
4. **Vendored libraries**: the `Libs/CREDITS.md` table, and which libraries lack upstream Forever support (kept until in-game evidence says otherwise).
5. **Open questions for Phases 1 and 3b**: per-file environment vs locals (the upvalue limit experience from Task 5), event facade, the virtual combat log timing (feasibility C.2), the GCD constant, spec identity 1491, the talent reader, whether to keep `SavedVariables: HekiliDB` or rename it, combo points and forms (unprobed), the deprecated shims that need `loadDeprecationFallbacks`.

Commit `docs: forever cleanup report` and push.
