-- Lint for the Forever branch. Every game read goes through ns.Facade (src/Hekili/Virtual/API/Facade.lua; see
-- tools/check_api_reads.sh): the names of tools/api_inventory.txt, CreateFrame among them, are deliberately NOT
-- declared here, so a bare read shows up as W113 "accessing undefined variable".
std = "lua51"
max_line_length = false
codes = true

exclude_files = {
    "src/Hekili/Libs/",
    "archive/",
    ".claude/",
    ".lua/",
    ".luacheckrc",
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
    "Hekili_OnAddonCompartmentClick", "Hekili_OnAddonCompartmentEnter",
    "Hekili_OnAddonCompartmentLeave", "Hekili_ToggleOptions", "Hekili_ToggleMode", "Hekili_TogglePause",
    "Hekili_SnapshotMode", "Hekili_ToggleCooldowns", "Hekili_ToggleDefensives", "Hekili_ToggleInterrupts",
    "Hekili_TogglePotions", "Hekili_ToggleEssences", "Hekili_ToggleCustom1", "Hekili_ToggleCustom2",
    "Hekili_ToggleDisplayMode", "Hekili_FixSpecialization", "HandleSpellData", "BlizzBlue",
    "HekiliPopupDropdownMixin", "HekiliPopupDropdownSliderMixin",
}

-- WoW Lua extensions, FrameXML utilities, other addons and constants that are not game-state reads.
-- The facade covers game-STATE READS only. Deliberately declared here because they are outside it: writes (SetCVar,
-- SetOverrideBindingClick, ClearOverrideBindings, ClearCursor, Screenshot), timers (C_Timer), secure hooks
-- (hooksecurefunc), profiling (debugprofilestop), secrecy predicates (issecretvalue, issecrettable, C_Secrets), and
-- UI widgets that read no game state (UIParent, GameTooltip). CreateFrame is the event facade's (Facade.CreateFrame).
read_globals = {
    -- Lua extensions provided by the client
    "wipe", "format", "strupper", "strlower", "strfind", "strsub", "strlen", "strsplit", "strjoin", "strtrim",
    "strmatch", "strrep", "strbyte", "strchar", "gmatch", "gsub", "tostringall", "tinsert", "tremove", "sort",
    "max", "min", "floor", "ceil", "abs", "date", "time", "bit", "debugstack", "debugprofilestop",
    "geterrorhandler", "seterrorhandler", "issecretvalue", "issecrettable", "C_Secrets",
    -- libraries and other addons
    "LibStub", "WeakAuras", "ElvUI", "ConsolePort", "SpellFlashCore", "Masque",
    -- FrameXML (Lua-defined UI utilities, not reads)
    "UIParent", "GameTooltip", "GameTooltip_SetTitle", "GameTooltip_AddNormalLine",
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
    -- client additions to the Lua standard tables
    table = { fields = { "wipe", "unpack" } },
    string = { fields = { "trim" } },
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
files["src/Hekili/Engine/Schema/Spec.lua"] = { globals = stateEnv }
files["src/Hekili/Engine/Sim/"] = { globals = stateEnv }
-- Options and Hekili.lua read no engine state either (Engine.Registry, the commands, Output.status); each keeps only
-- upstream's stray global reads.
files["src/Hekili/Options/Options.lua"] = {
    globals = { "actual_trinket1", "actual_trinket2", "actual_main_hand", "QueueRebuildUI" },
}
files["src/Hekili/Options/DevTools.lua"] = {
    globals = { "assignAuraToLastCast", "trackAuraApplication", "trackAuraRemoval" },
}
-- UI.lua reads no engine state (Engine.Registry, Engine.Output.status): not stateEnv, so a bare state/class fails.
files["src/Hekili/UI/UI.lua"] = { globals = { "p", "alphaCheck" } } -- upstream's two stray global reads
-- The names a class file's `now` function reads in VirtualState's context (src/Hekili/Virtual/State/Families/Now.lua).
local nowEnv = {
    "gain", "spend", "applyBuff", "applyDebuff", "removeBuff", "removeDebuff", "addStack", "setCooldown", "talent",
    "buff", "debuff", "knownRank", "now", "combat", "rage", "energy", "mana", "focus", "runic_power",
}
files["tests/Virtual/State/"] = { std = "+busted", read_globals = nowEnv }
files["tests/Virtual/Events/"] = { std = "+busted", read_globals = nowEnv }
files["tests/Virtual/API/"] = { std = "+busted", read_globals = nowEnv }
files["tests/Virtual/harness/"] = { std = "+busted" }
files["tests/Forever/"] = { std = "+busted" }
-- The Warrior's handlers, state expressions and state functions run with setfenv( f, state ) as well; these are the
-- further `state` names they use.
local warriorEnv = {
    "rage", "cooldown", "combat", "active_enemies", "active_dot", "setDistance", "interrupt", "swap_stance",
    "should_queue", "mainhand_remains", "nextMH", "mainhand_speed", "offensive_cost",
}
for _, k in ipairs(stateEnv) do
    warriorEnv[#warriorEnv + 1] = k
end
files["src/Hekili/Forever/Classes/Warrior.lua"] = { globals = warriorEnv }
-- The Druid's further `state` names.
local druidEnv = {
    "rage", "energy", "mana", "combo_points", "cooldown", "combat", "group", "swap_form", "addStack", "removeStack",
}
for _, k in ipairs(stateEnv) do
    druidEnv[#druidEnv + 1] = k
end
files["src/Hekili/Forever/Classes/Druid.lua"] = { globals = druidEnv }
files["src/Hekili/Forever/Races/"] = { globals = stateEnv }
files["src/Hekili/Forever/Shared/"] = { globals = stateEnv }
