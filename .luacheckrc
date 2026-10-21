-- Lint for the Forever branch. Every game read goes through ns.Facade (src/Hekili/Game/API/Facade.lua; see
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
    "COMBATLOG_OBJECT_REACTION_FRIENDLY",
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
    "next_ation", "name", "listName", "id", "event", "boss", "abilitty", "display", "args", "v", "p",
    "val", "treeToString", "QueueRebuildUI",
    -- the belief's reads content uses (State.lua, restructure plan Task 8)
    "knownRank", "stat", "swingBase", "healthMax",
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
files["src/Hekili/UI/UI.lua"] = { globals = { "p" } } -- upstream's stray global read
-- The names a class file's `now` function reads in VirtualState's context (src/Hekili/Game/State/Families/Now.lua).
local nowEnv = {
    "gain", "spend", "applyBuff", "applyDebuff", "removeBuff", "removeDebuff", "addStack", "setCooldown", "summonTotem",
    "summonPet", "dismissPet", "reduceCooldown", "level",
    "talent",
    "buff", "debuff", "knownRank", "stat", "swingBase", "healthMax", "now", "combat", "rage", "energy", "mana", "focus",
    "runic_power",
}
files["tests/Game/State/"] = { std = "+busted", read_globals = nowEnv }
files["tests/Game/Events/"] = { std = "+busted", read_globals = nowEnv }
files["tests/Game/API/"] = { std = "+busted", read_globals = nowEnv }
files["tests/Game/harness/"] = { std = "+busted" }
files["tests/Forever/"] = { std = "+busted" }
-- The Warrior's handlers, state expressions and state functions run with setfenv( f, state ) as well; these are the
-- further `state` names they use.
local warriorEnv = {
    "rage", "cooldown", "combat", "active_enemies", "active_dot", "setDistance", "interrupt", "swap_stance",
    "mainhand_remains", "nextMH", "mainhand_speed",
}
for _, k in ipairs(stateEnv) do
    warriorEnv[#warriorEnv + 1] = k
end
files["src/Hekili_Warrior/Warrior.lua"] = { globals = warriorEnv }
-- The Druid's further `state` names.
local druidEnv = {
    "rage", "energy", "mana", "combo_points", "cooldown", "combat", "group", "swap_form", "addStack", "removeStack",
    "level",
}
for _, k in ipairs(stateEnv) do
    druidEnv[#druidEnv + 1] = k
end
files["src/Hekili_Druid/Druid.lua"] = { globals = druidEnv }
-- The Rogue's further `state` names.
local rogueEnv = {
    "energy", "combo_points", "cooldown", "combat", "class", "interrupt", "stealthed", "expose_due",
}
for _, k in ipairs(stateEnv) do
    rogueEnv[#rogueEnv + 1] = k
end
files["src/Hekili_Rogue/Rogue.lua"] = { globals = rogueEnv }
-- The Paladin's further `state` names.
local paladinEnv = { "combat", "seal_up", "nextMH", "mainhand_speed", "query_time" }
for _, k in ipairs(stateEnv) do
    paladinEnv[#paladinEnv + 1] = k
end
files["src/Hekili_Paladin/Paladin.lua"] = { globals = paladinEnv }
-- The Shaman's further `state` names.
local shamanEnv = { "totem", "summonTotem" }
for _, k in ipairs(stateEnv) do
    shamanEnv[#shamanEnv + 1] = k
end
files["src/Hekili_Shaman/Shaman.lua"] = { globals = shamanEnv }
-- The Hunter's further `state` names.
local hunterEnv = { "summonPet", "combat", "nextMH", "mainhand_speed" }
for _, k in ipairs(stateEnv) do
    hunterEnv[#hunterEnv + 1] = k
end
files["src/Hekili_Hunter/Hunter.lua"] = { globals = hunterEnv }
-- The Mage's further `state` names.
local mageEnv =
    { "addStack", "removeStack", "interrupt", "min", "locked_out_arcane", "locked_out_fire", "locked_out_frost" }
for _, k in ipairs(stateEnv) do
    mageEnv[#mageEnv + 1] = k
end
files["src/Hekili_Mage/Mage.lua"] = { globals = mageEnv }
-- The Priest's further `state` names.
local priestEnv = { "locked_out_arcane", "locked_out_holy", "locked_out_shadow" }
for _, k in ipairs(stateEnv) do
    priestEnv[#priestEnv + 1] = k
end
files["src/Hekili_Priest/Priest.lua"] = { globals = priestEnv }
-- The Warlock's further `state` names.
local warlockEnv = {
    "min", "max", "level", "summonPet", "soul_shards", "locked_out_shadow", "locked_out_fire",
}
for _, k in ipairs(stateEnv) do
    warlockEnv[#warlockEnv + 1] = k
end
files["src/Hekili_Warlock/Warlock.lua"] = { globals = warlockEnv }
files["src/Hekili_Shared/Races/"] = { globals = stateEnv }
files["src/Hekili_Shared/Shared/"] = { globals = stateEnv }
