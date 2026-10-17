-- tests/Virtual/harness/headless.lua (headless loop design §1): stock Hekili loaded headless under busted, one
-- instance per Lua environment. Every chunk of Hekili.toc runs with setfenv( chunk, H.env ), so two instances (ours and
-- the oracle, §4) keep their own `Hekili`, `LibStub`, frames and saved variables, and the real _G gains nothing. The
-- client is fake_api (copied per instance, each with its own `ctl`); this file holds only load and UI scaffolding
-- (WoW's Lua aliases, frames, C_Timer, constants), never a client answer a secret could touch (§1.2).
-- Process-wide effect, the only one: `string.trim` and `string.split` (WoW adds them; Hekili calls `s:trim()`, which
-- reads the one string metatable), idempotent additions to the real `string` table.
-- Class-neutral (the boundary rule): the character (class, spec, spells, talents) comes from the content.
local fake = require("Virtual.State.helpers.fake_api")

local M = {}

M.ROOT = "src/Hekili/"
M.SETTLE = 5 -- seconds the clock runs after login before the instance is handed over
-- The one file the loader skips, and why.
M.SKIPPED = { ["src/Hekili/UI/PopupSlider.xml"] = "XML frames (no XML frame loader headless; not on the queue path)" }

-- Reads of unset globals while the TOC loads and at login: feature probes the client also answers nil (other
-- addons, retail- or classic-only names). A name not listed fails `H.unexpected` (§1.4): a person decides.
M.KNOWN_LOAD_NILS = {
    ElvUI = "another addon (Hekili skins for it when present)",
    WeakAuras = "another addon",
    io = "LibDeflate.lua:3453 probes the standalone Lua io library (absent in WoW)",
    SpellFlashCore = "an optional library's host addon",
    ChatThrottleLib = "AceComm's optional global (it embeds its own)",
    ["LibDualSpec-1.0-35 test"] = "LibStub probes a minor version",
    LibStub = "LibStub.lua's own `_G.LibStub` probe before it defines it",
    HekiliDB = "no saved variables (a fresh profile)",
    HekiliCustomEditorInsertLink = "Hekili's own probe of an optional hook",
    AceGUIEditBoxInsertLink = "AceGUI's own probe",
    AceGUIMultiLineEditBoxInsertLink = "AceGUI's own probe",
    ChatEdit_InsertLink = "chat UI (not on Forever's headless client)",
    ChatEdit_SendText = "chat UI",
    ChatFrameUtil = "chat UI (retail)",
    C_EventUtils = "retail-only namespace",
    C_BattleNet = "retail-only namespace",
    C_PaperDollInfo = "retail-only namespace",
    BNSendGameData = "Battle.net messaging",
    Ambiguate = "chat name helper",
    AnimateTexCoords = "UI animation helper",
    TextureUtil = "retail UI helper",
    ClearCursor = "cursor UI",
    CheckInteractDistance = "a range library's fallback probe",
    IsSpellInRange = "a range library's legacy probe (C_Spell.IsSpellInRange answers)",
    UnitIsVisible = "a range library's probe",
    GetPlayerMapPosition = "a range library's legacy probe",
    GetInventoryItemLink = "a range library's item probe",
    GetSpellInfo = "the legacy global (C_Spell.GetSpellInfo answers)",
    GetNumSpellTabs = "legacy spellbook API (absent on the modern client)",
    GetSpellTabInfo = "legacy spellbook API",
    GetSpellBookItemInfo = "legacy spellbook API",
    GetSpellBookItemName = "legacy spellbook API",
    BOOKTYPE_SPELL = "legacy spellbook constant",
    LEVEL_LINKED_NOT_USABLE = "a GlobalString nothing on the queue path reads",
    SPELL_FAILED_INCORRECT_AREA = "a GlobalString nothing on the queue path reads",
    SPELL_FAILED_NOT_HERE = "a GlobalString nothing on the queue path reads",
    SPELL_FAILED_NOT_IN_MAGE_TOWER = "a GlobalString nothing on the queue path reads",
    TOOLTIP_NOT_IN_MAGE_TOWER = "a GlobalString nothing on the queue path reads",
    TALENT_SPEC_PRIMARY = "a GlobalString nothing on the queue path reads",
    TALENT_SPEC_SECONDARY = "a GlobalString nothing on the queue path reads",
    LE_EXPANSION_CATACLYSM = "a classic flavour constant",
    LE_EXPANSION_MISTS_OF_PANDARIA = "a classic flavour constant",
    WOW_PROJECT_ID = "the flavour probes: none matches, as on Forever",
    WOW_PROJECT_MAINLINE = "the flavour probes",
    WOW_PROJECT_CLASSIC = "the flavour probes",
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = "the flavour probes",
    WOW_PROJECT_WRATH_CLASSIC = "the flavour probes",
    WOW_PROJECT_CATACLYSM_CLASSIC = "the flavour probes",
    WOW_PROJECT_MISTS_CLASSIC = "the flavour probes",
    id = "Hekili reads an unset global `id` (an upstream slip, nil in game too)",
    squawk = "Scripts.lua:1032 reads an unset global (upstream, nil in game too)",
    -- namespace members: the facade's five passthrough rows absent on Forever, and LibSpellRange's load probes
    ["C_SpellBook.GetSpellBookItemInfo"] = "facade row absent on Forever (retail spellbook item API)",
    ["C_SpellBook.GetSpellBookSkillLineInfo"] = "facade row absent on Forever (retail spellbook tabs API)",
    ["C_Traits.GetNodeCost"] = "facade row absent on Forever (retail talent currency)",
    ["C_Traits.GetSubTreeInfo"] = "facade row absent on Forever (retail hero talents)",
    ["C_Traits.GetTreeCurrencyInfo"] = "facade row absent on Forever (retail talent currency)",
    ["C_Spell.SpellHasRange"] = "LibSpellRange-1.0.lua:47 probe (fake_api has no row; not on the queue path)",
    ["C_SpellBook.GetSpellBookItemName"] = "LibSpellRange-1.0.lua:64 fallback probe (not on the queue path)",
}
-- Reads of unset globals at recommendation time (upstream slips, nil in game too: SPIKE risk 10).
M.KNOWN_RUN_NILS = {
    overcap = "State.lua:1385",
    id = "State.lua:3765",
    listName = "Core.lua:1992",
    alphaCheck = "UI.lua:1121",
    squawk = "Scripts.lua:1032",
    WeakAuras = "another addon's probe on the display path",
}

-- WoW's string additions, process-wide (the header's one shared effect).
function string.trim(s) -- luacheck: ignore 122 142
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function strsplit(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
        out[#out + 1] = piece
    end
    return unpack(out)
end
function string.split(s, sep) -- luacheck: ignore 122 142
    return strsplit(sep, s)
end

-- The Lua standard library the client offers, copied into each environment.
local STD = {
    "assert",
    "error",
    "ipairs",
    "pairs",
    "next",
    "select",
    "type",
    "tostring",
    "tonumber",
    "rawget",
    "rawset",
    "rawequal",
    "setmetatable",
    "getmetatable",
    "pcall",
    "unpack",
    "setfenv",
    "newproxy",
    "collectgarbage",
    "gcinfo",
    "string",
    "math",
    "os",
    "coroutine",
    "debug",
    "load",
}

-- A Lua 5.1 bit library (WoW's `bit`), for the libraries that read it at load.
local function bitop(a, b, f)
    local r, m = 0, 1
    while a > 0 or b > 0 do
        if f(a % 2, b % 2) then
            r = r + m
        end
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
    end
    return r
end
local BIT = {
    band = function(a, b)
        return bitop(a, b, function(x, y)
            return x == 1 and y == 1
        end)
    end,
    bor = function(a, b)
        return bitop(a, b, function(x, y)
            return x == 1 or y == 1
        end)
    end,
    lshift = function(a, n)
        return a * 2 ^ n
    end,
    rshift = function(a, n)
        return math.floor(a / 2 ^ n)
    end,
    bnot = function(a)
        return -1 - a
    end,
}

-- Stub widgets: a frame whose unknown WoW-style methods are no-ops; `Get*` answers a stub, `Is*`/`Has*` false, a short
-- list of getters numbers; any other missing key reads nil, so Hekili's own fields on a frame behave.
local VERBS = {
    "Set",
    "Get",
    "Is",
    "Has",
    "Create",
    "Register",
    "Unregister",
    "Enable",
    "Disable",
    "Show",
    "Hide",
    "Clear",
    "Hook",
    "Raise",
    "Lower",
    "Start",
    "Stop",
    "Play",
    "Add",
    "Lock",
    "Unlock",
    "Release",
    "Adjust",
    "Insert",
    "Remove",
    "Scroll",
    "Update",
    "Click",
    "Refresh",
    "Fade",
    "Desaturate",
    "Toggle",
    "Restart",
    "Finish",
    "Pause",
    "Can",
    "Apply",
    "Reset",
    "Clip",
    "Disconnect",
    "Scale",
}
local NUM = {
    GetWidth = 100,
    GetHeight = 100,
    GetScale = 1,
    GetEffectiveScale = 1,
    GetAlpha = 1,
    GetLeft = 0,
    GetRight = 0,
    GetTop = 0,
    GetBottom = 0,
    GetNumPoints = 0,
    GetFrameLevel = 1,
    GetID = 0,
    GetValue = 0,
    GetNumRegions = 0,
    GetNumChildren = 0,
    GetStringWidth = 10,
    GetStringHeight = 10,
    GetCenter = 0,
    GetEffectiveAlpha = 1,
    GetFrameStrata = "MEDIUM",
    GetObjectType = "Frame",
    GetText = "",
    GetFont = "Fonts\\FRIZQT__.TTF",
    GetTexture = 0,
    HasScript = true,
}
local function isVerb(k)
    for _, v in ipairs(VERBS) do
        if k:sub(1, #v) == v and (k == v or k:sub(#v + 1, #v + 1):match("%u")) then
            return true
        end
    end
end

--- A new instance: Hekili loaded and logged in. `o.character` (the content's, set before login: §1.3) {
--- class, classID, specID, level, known = { spellID... }, talents = { [spellID] = rank }, power = { type, token, max,
--- value }, speed = { main, off }, forms = { spellID... }, form }; `o.pack` the priority to select; `o.now` the clock [1000].
--- Returns `H = { env, api, ctl, ns, Hekili, frames, timers, misses, errors, loadErrors, prints }`.
function M.new(o)
    o = o or {}
    local api, ctl = fake.new()
    ctl.now = o.now or 1000
    local H = { api = api, ctl = ctl, frames = {}, timers = {}, errors = {}, loadErrors = {}, prints = {} }
    H.phase, H.misses = "load", { load = {}, login = {}, run = {} }
    local env = {}
    H.env = env
    env._G = env
    for _, k in ipairs(STD) do
        env[k] = _G[k]
    end
    env.table = setmetatable({}, { __index = table })
    -- loadstring binds the real globals in 5.1: Scripts.lua compiles the APL with it, so bind them to the instance
    function env.loadstring(s, name)
        local f, err = loadstring(s, name)
        if f then
            setfenv(f, env)
        end
        return f, err
    end
    function env.getfenv(f) -- getfenv(0) is the thread's globals: LibSharedMedia reads them
        if f == 0 then
            return env
        end
        return getfenv(type(f) == "number" and f + 1 or f or 2)
    end
    -- WoW's xpcall passes extra arguments to the function (AceAddon's safecall relies on it)
    function env.xpcall(f, h, ...)
        local n = select("#", ...)
        if n == 0 then
            return xpcall(f, h)
        end
        local args = { ... }
        return xpcall(function()
            return f(unpack(args, 1, n))
        end, h)
    end
    -- the client: fake_api's functions, namespaces copied so an instance's writes stay its own
    for k, v in pairs(api) do
        if k ~= "ctl" then
            local mt = { __index = v }
            if k:match("^C_") then -- an absent member read through a namespace counts as a miss (§1.4)
                function mt.__index(_, key)
                    local x = v[key]
                    if x == nil then
                        local t, name = H.misses[H.phase], k .. "." .. tostring(key)
                        t[name] = (t[name] or 0) + 1
                    end
                    return x
                end
            end
            env[k] = type(v) == "table" and setmetatable({}, mt) or v
        end
    end

    -- WoW's Lua aliases
    env.floor, env.ceil, env.max, env.min, env.abs = math.floor, math.ceil, math.max, math.min, math.abs
    env.format, env.strlower, env.strupper, env.gmatch = string.format, string.lower, string.upper, string.gmatch
    env.strsub, env.strfind, env.strmatch, env.gsub = string.sub, string.find, string.match, string.gsub
    env.strlen, env.strrep, env.strbyte, env.strchar = string.len, string.rep, string.byte, string.char
    env.tinsert, env.tremove, env.sort, env.tconcat = table.insert, table.remove, table.sort, table.concat
    function env.wipe(t)
        for k in pairs(t) do
            t[k] = nil
        end
        return t
    end
    env.table.wipe = env.wipe
    env.strtrim, env.strsplit = string.trim, strsplit
    function env.strjoin(sep, ...)
        return table.concat({ ... }, sep)
    end
    function env.tostringall(...)
        local n, t = select("#", ...), { ... }
        for i = 1, n do
            t[i] = tostring(t[i])
        end
        return unpack(t, 1, n)
    end
    function env.tContains(t, v)
        for _, x in pairs(t) do
            if x == v then
                return true
            end
        end
        return false
    end
    env.date, env.time, env.bit = os.date, os.time, BIT
    -- wall clock for Hekili's frame budget only; the loop calls Update directly and never reaches it (§1.3)
    function env.debugprofilestop()
        return os.clock() * 1000
    end
    function env.debugstack()
        return debug.traceback("", 2)
    end
    function env.geterrorhandler()
        return function(e)
            H.errors[#H.errors + 1] = tostring(e)
        end
    end
    env.seterrorhandler = function() end
    function env.securecallfunction(f, ...)
        return f(...)
    end
    function env.hooksecurefunc(a, b, c)
        local t, name, hook = a, b, c
        if type(a) == "string" then
            t, name, hook = env, a, b
        end
        local orig = t[name]
        t[name] = function(...)
            local r = { orig(...) }
            hook(...)
            return unpack(r)
        end
    end
    function env.print(...)
        H.prints[#H.prints + 1] = table.concat({ env.tostringall(...) }, " ")
    end
    function env.issecurevariable()
        return true
    end
    function env.Mixin(t, ...)
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do
                t[k] = v
            end
        end
        return t
    end
    function env.CreateFromMixins(...)
        return env.Mixin({}, ...)
    end

    -- stub widgets and frames (real event registration and scripts)
    local stubMT, methods = {}, {}
    local function stub(name)
        return setmetatable({ __stub = name or "?" }, stubMT)
    end
    local function frame(kind, name, parent)
        local f = stub(kind)
        rawset(f, "__name", name)
        rawset(f, "__parent", parent)
        rawset(f, "__events", {})
        rawset(f, "__scripts", {})
        if name then
            env[name] = f
        end
        H.frames[#H.frames + 1] = f
        return f
    end
    H.stub, H.CreateFrame = stub, frame
    stubMT.__index = function(_, k)
        if type(k) ~= "string" then
            return nil
        end
        local m = methods[k]
        if m then
            return m
        end
        if NUM[k] ~= nil then
            local v = NUM[k]
            m = function()
                return v
            end
        elseif k:match("^Is") or k:match("^Has") then
            m = function()
                return false
            end
        elseif k:match("^Get") then
            m = function()
                return stub(k)
            end
        elseif k:match("^Create") then
            m = function(self, name)
                return frame("Region", type(name) == "string" and name or nil, self)
            end
        elseif isVerb(k) then
            m = function(self)
                return self
            end
        else
            return nil
        end
        methods[k] = m
        return m
    end
    function methods.GetSize()
        return 100, 100
    end
    function methods.GetPoint()
        return "CENTER", nil, "CENTER", 0, 0
    end
    function methods.GetTextColor()
        return 1, 1, 1, 1
    end
    methods.GetVertexColor = methods.GetTextColor
    function methods.GetTexCoord()
        return 0, 1, 0, 1
    end
    function methods.GetName(self)
        return rawget(self, "__name")
    end
    function methods.GetParent(self)
        return rawget(self, "__parent")
    end
    methods.GetChildren, methods.GetRegions, methods.GetAttribute, methods.GetScript = nil, nil, nil, nil
    function methods.RegisterEvent(self, e)
        self.__events[e] = true
        return true
    end
    methods.RegisterUnitEvent = methods.RegisterEvent
    function methods.UnregisterEvent(self, e)
        self.__events[e] = nil
    end
    function methods.UnregisterAllEvents(self)
        env.wipe(self.__events)
    end
    function methods.IsEventRegistered(self, e)
        return self.__events[e] == true
    end
    function methods.SetScript(self, s, fn)
        self.__scripts[s] = fn
    end
    function methods.HookScript(self, s, fn)
        local old = self.__scripts[s]
        self.__scripts[s] = old and function(...)
            old(...)
            fn(...)
        end or fn
    end
    function methods.GetScript(self, s)
        return self.__scripts[s]
    end
    env.CreateFrame = frame

    --- Delivers `event` to every frame that registered it (the client's dispatch); ctl.Fire is this.
    function H.Fire(event, ...)
        for _, f in ipairs(H.frames) do
            local fn = rawget(f, "__events") and f.__events[event] and f.__scripts.OnEvent
            if fn then
                fn(f, event, ...)
            end
        end
    end
    ctl.Fire = H.Fire

    -- C_Timer on the fake clock: callbacks by due time, run by H.RunTimers(now)
    local seq = 0
    local function addTimer(d, fn, iter)
        seq = seq + 1
        local t = { at = ctl.now + d, fn = fn, d = d, iter = iter, seq = seq }
        function t.Cancel(self)
            self.cancelled = true
        end
        function t.IsCancelled(self)
            return self.cancelled
        end
        H.timers[#H.timers + 1] = t
        return t
    end
    env.C_Timer = {
        After = function(d, fn)
            addTimer(d, fn, 1)
        end,
        NewTimer = function(d, fn)
            return addTimer(d, fn, 1)
        end,
        NewTicker = function(d, fn, n)
            return addTimer(d, fn, n or math.huge)
        end,
    }
    --- Runs every timer due at or before `now`, in due order (a raise is recorded in H.errors).
    --- Each callback sees its own due time as GetTime(); the clock is restored after it.
    function H.RunTimers(now)
        while true do
            local t, ti
            for i = #H.timers, 1, -1 do
                local x = H.timers[i]
                if x.cancelled then
                    table.remove(H.timers, i)
                    if ti then
                        ti = ti - 1
                    end
                elseif x.at <= now and (not t or x.at < t.at or (x.at == t.at and x.seq < t.seq)) then
                    t, ti = x, i
                end
            end
            if not t then
                return
            end
            local at, saved = t.at, ctl.now
            t.iter = t.iter - 1
            if t.iter <= 0 then
                table.remove(H.timers, ti)
            else
                t.at = t.at + t.d
            end
            ctl.now = at
            local ok, err = pcall(t.fn, t)
            ctl.now = saved
            if not ok then
                H.errors[#H.errors + 1] = "timer: " .. tostring(err)
            end
        end
    end

    -- Hekili's and the libraries' load reads: constants, UI globals, item and spell loaders
    env.Item = {
        CreateFromItemID = function(_, id)
            return {
                IsItemEmpty = function()
                    return false
                end,
                ContinueOnItemLoad = function(_, fn)
                    fn(true)
                end,
                GetItemName = function()
                    return "Item " .. id
                end,
                GetItemLink = function()
                    return "[Item " .. id .. "]"
                end,
                GetItemIcon = function()
                    return 0
                end,
                GetItemID = function()
                    return id
                end,
            }
        end,
    }
    env.Spell = {
        CreateFromSpellID = function()
            return {
                IsSpellEmpty = function()
                    return false
                end,
                ContinueOnSpellLoad = function(_, fn)
                    fn(true)
                end,
            }
        end,
    }
    -- Enum: the power types; any other Enum table answers a fresh number per key (enough at load)
    local function anyNumber()
        local n = 100
        return setmetatable({}, {
            __index = function(t, k)
                n = n + 1
                rawset(t, k, n)
                return n
            end,
        })
    end
    env.Enum = setmetatable({
        PowerType = {
            HealthCost = -2,
            None = -1,
            Mana = 0,
            Rage = 1,
            Focus = 2,
            Energy = 3,
            ComboPoints = 4,
            Runes = 5,
            RunicPower = 6,
            SoulShards = 7,
            LunarPower = 8,
            HolyPower = 9,
            Alternate = 10,
            Maelstrom = 11,
            Chi = 12,
            Insanity = 13,
            Obsolete = 14,
            Obsolete2 = 15,
            ArcaneCharges = 16,
            Fury = 17,
            Pain = 18,
            Essence = 19,
        },
    }, {
        __index = function(t, k)
            local v = anyNumber()
            rawset(t, k, v)
            return v
        end,
    })
    for _, s in ipairs({
        "ACCEPT",
        "CANCEL",
        "OKAY",
        "NONE",
        "YES",
        "NO",
        "CLOSE",
        "DEFAULT",
        "INVTYPE_WEAPONMAINHAND",
        "BATTLE_PET_NAME_4",
        "PET_TYPE_DEMON",
        "ITEM_SPELL_TRIGGER_ONEQUIP",
        "KEY_BUTTON1",
        "KEY_BUTTON2",
        "NOT_BOUND",
        "RESET",
        "SAVE",
    }) do
        env[s] = s
    end
    local function self(_, k)
        return k
    end
    env.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = self })
    env.LOCALIZED_CLASS_NAMES_FEMALE = env.LOCALIZED_CLASS_NAMES_MALE
    env.RAID_CLASS_COLORS = setmetatable({}, {
        __index = function()
            return { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
        end,
    })
    env.MAX_PLAYER_LEVEL, env.INVSLOT_LAST_EQUIPPED, env.TOOLTIP_UPDATE_TIME = 60, 19, 0.2
    env.COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x10
    env.NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
    env.BackdropTemplateMixin = {}
    env.UIParent = frame("Frame", "UIParent")
    env.GameTooltip = frame("GameTooltip", "GameTooltip")
    env.DEFAULT_CHAT_FRAME = frame("Frame", "DEFAULT_CHAT_FRAME")
    env.Minimap = frame("Minimap", "Minimap")
    env.ChatFontNormal = stub("Font")
    for _, f in ipairs({
        "GameFontNormal",
        "GameFontHighlight",
        "GameFontHighlightSmall",
        "GameFontNormalSmall",
        "GameFontNormalLarge",
        "GameFontHighlightLarge",
        "GameFontDisable",
        "GameFontDisableSmall",
        "ChatFontSmall",
        "GameFontHighlightMedium",
        "GameFontNormalHuge",
        "NumberFontNormal",
        "SystemFont_Shadow_Med1",
    }) do
        env[f] = stub(f)
    end
    env.PixelUtil = setmetatable({ -- numbers, not stubs (UI.lua:121)
        GetNearestPixelSize = function(x)
            return x
        end,
        GetPixelToUIUnitFactor = function()
            return 1
        end,
    }, {
        __index = function()
            return function() end
        end,
    })
    env.AddonCompartmentFrame = stub("AddonCompartmentFrame")
    env.Settings = stub("Settings")
    env.SlashCmdList, env.hash_SlashCmdList, env.UISpecialFrames, env.StaticPopupDialogs = {}, {}, {}, {}
    local noop = function() end
    for _, k in ipairs({
        "InterfaceOptions_AddCategory",
        "UIDropDownMenu_AddButton",
        "UIDropDownMenu_AddSeparator",
        "UIDropDownMenu_SetDisplayMode",
        "ToggleDropDownMenu",
        "UIFrameFadeOut",
        "GameTooltip_SetTitle",
        "GameTooltip_AddNormalLine",
        "ChatFrame_AddMessageEventFilter",
        "PlaySound",
        "GetMouseFocus",
        "RegisterAddonMessagePrefix",
        "SendChatMessage",
        "SetCVar",
        "ClearOverrideBindings",
        "SetOverrideBindingClick",
    }) do
        env[k] = noop
    end
    function env.CreateAtlasMarkup()
        return ""
    end
    function env.GetAppropriateTooltip()
        return env.GameTooltip
    end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    function env.GetScreenWidth()
        return 1920
    end
    function env.GetScreenHeight()
        return 1080
    end
    local function no()
        return false
    end
    env.IsShiftKeyDown, env.IsControlKeyDown, env.IsAltKeyDown = no, no, no
    function env.CreateColor(r, g, b, a)
        return {
            r = r,
            g = g,
            b = b,
            a = a,
            GetRGBA = function(c)
                return c.r, c.g, c.b, c.a
            end,
        }
    end
    env.SOUNDKIT = setmetatable({}, {
        __index = function()
            return 0
        end,
    })
    env.C_ChatInfo = { RegisterAddonMessagePrefix = noop, SendAddonMessage = noop }
    function env.GetChannelName()
        return 0
    end
    env.FONT_COLOR_CODE_CLOSE, env.HIGHLIGHT_FONT_COLOR_CODE, env.NORMAL_FONT_COLOR_CODE =
        "|r", "|cffffffff", "|cffffd100"
    -- library reads at load
    function env.GetCurrentRegion()
        return 1
    end
    env.C_UIFileAsset = {
        IsKnownFile = function()
            return true
        end,
    }
    function env.GetInventorySlotInfo()
        return 1
    end
    function env.GetMinimapShape()
        return "ROUND"
    end
    function env.ClassicExpansionAtLeast()
        return false
    end
    env.ClassicExpansionAtMost = env.ClassicExpansionAtLeast
    env.LE_EXPANSION_SHADOWLANDS, env.LE_EXPANSION_CLASSIC, env.LE_EXPANSION_LEVEL_CURRENT = 8, 0, 0
    function env.GetNumSpecGroups()
        return 1
    end
    env.GetActiveSpecGroup = env.GetNumSpecGroups
    local function pool()
        return {
            Acquire = function()
                return frame("Region")
            end,
            Release = noop,
            ReleaseAll = noop,
            EnumerateActive = function()
                return noop
            end,
        }
    end
    env.CreateTexturePool, env.CreateFramePool, env.CreateObjectPool, env.CreateFontStringPool = pool, pool, pool, pool
    local loggedIn = false
    function env.IsLoggedIn()
        return loggedIn
    end

    -- the miss counter: every read of a name nobody defined, by phase (§1.4)
    setmetatable(env, {
        __index = function(_, k)
            local t = H.misses[H.phase]
            t[k] = (t[k] or 0) + 1
            return nil
        end,
    })

    -- the loader: Hekili.toc in order, an .xml line's Script/Include tags; a raising file is recorded, the load goes on
    -- ns.Error, counted (the engine-health metric) from the moment Utils.lua defines it, so the copies files take
    -- at load (State.lua's `local Error = ns.Error`) and Hekili:Error all count
    local ns = setmetatable({}, {
        __newindex = function(t, k, v)
            if k == "Error" and type(v) == "function" then
                local onError = v
                v = function(output, ...)
                    H.errors[#H.errors + 1] = tostring(output)
                    return onError(output, ...)
                end
            end
            rawset(t, k, v)
        end,
    })
    H.ns = ns
    local function loadLua(path)
        local f, err = loadfile(path)
        if not f then
            H.loadErrors[#H.loadErrors + 1] = path .. ": " .. tostring(err)
            return
        end
        setfenv(f, env)
        local ok, e = xpcall(function()
            return f("Hekili", ns)
        end, debug.traceback)
        if not ok then
            H.loadErrors[#H.loadErrors + 1] = path .. ": " .. tostring(e)
        end
    end
    local function loadXml(path)
        local fh = io.open(path)
        if not fh then
            H.loadErrors[#H.loadErrors + 1] = path .. ": missing"
            return
        end
        local body = fh:read("*a"):gsub("<!%-%-.-%-%->", "")
        fh:close()
        local dir = path:match("^(.*/)") or ""
        for tag, file in body:gmatch('<(%a+)%s+file%s*=%s*"([^"]+)"') do
            local p = dir .. file:gsub("\\", "/")
            if tag == "Script" then
                loadLua(p)
            elseif tag == "Include" then
                loadXml(p)
            end
        end
        if not M.SKIPPED[path] and (body:match("<Frame") or body:match("<Button") or body:match("<Slider")) then
            H.loadErrors[#H.loadErrors + 1] = path .. ": XML frames not loaded"
        end
    end

    local c = o.character
    if c then -- the character, before login: VirtualState builds its spellbook at SpecializationChanged
        ctl.class, ctl.classID, ctl.specID = c.class, c.classID or 0, c.specID
        ctl.level.player = c.level
        for _, id in ipairs(c.known or {}) do
            ctl.known[id] = true
        end
        if c.talents then
            local tr = { config = 1, trees = { 1 }, nodeIDs = {}, nodes = {}, defs = {} }
            for spell, rank in pairs(c.talents) do
                local n = #tr.nodeIDs + 1
                tr.nodeIDs[n], tr.nodes[n], tr.defs[n] = n, { entryIDs = { n }, activeRank = rank }, spell
            end
            ctl.traits = tr
        end
        local p = c.power
        if p then
            ctl.powerType[1], ctl.powerType[2] = p.type, p.token
            ctl.powerMax[p.type], ctl.power[p.type] = p.max, p.value or 0
        end
        if c.speed then
            ctl.speed = c.speed
        end
        for i, id in ipairs(c.forms or {}) do
            ctl.forms[i] = id
        end
        ctl.form = c.form or 0
    end
    for line in io.lines(M.ROOT .. "Hekili.toc") do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^##") then
            local p = M.ROOT .. line:gsub("\\", "/")
            if p:match("%.xml$") then
                loadXml(p)
            else
                loadLua(p)
            end
        end
    end

    -- login: ADDON_LOADED (OnInitialize, the AceDB profile), PLAYER_LOGIN (OnEnable, VS.Start), PLAYER_ENTERING_WORLD
    H.phase = "login"
    local ok, err = xpcall(function()
        H.Fire("ADDON_LOADED", "Hekili")
        loggedIn = true
        H.Fire("PLAYER_LOGIN")
        H.Fire("PLAYER_ENTERING_WORLD", true, false)
    end, debug.traceback)
    if not ok then
        H.loadErrors[#H.loadErrors + 1] = "login: " .. tostring(err)
    end
    -- the seconds after login: the display visibility (UI.lua:2102, +3 s) and the spec's pack review (+5 s) run
    ctl.now = ctl.now + M.SETTLE
    H.RunTimers(ctl.now)
    H.Hekili = rawget(env, "Hekili")
    local hk = H.Hekili
    if hk and o.pack and ctl.specID then
        rawget(hk.DB.profile.specs, ctl.specID).package = o.pack
    end
    H.phase = "run"
    return H
end

--- The names `H` read in `phase` that the phase's list does not hold (load and login: KNOWN_LOAD_NILS; run:
--- KNOWN_RUN_NILS), sorted.
function M.unexpected(H, phase)
    local known = phase == "run" and M.KNOWN_RUN_NILS or M.KNOWN_LOAD_NILS
    local out = {}
    for k in pairs(H.misses[phase]) do
        if not known[k] then
            out[#out + 1] = tostring(k)
        end
    end
    table.sort(out)
    return out
end

--- One display cycle at `t`: the clock, the VirtualState frame's OnUpdate (the staged flush), the due timers, then
--- Hekili.Update() called directly (never the wall-clock budgeted frame update: §2.2). Returns false and the error
--- when Update raised.
function M.cycle(H, t)
    local ctl = H.ctl
    ctl.now = t
    local f = H.ns.VirtualStateInternal.Events.frame
    local u = f and f.__scripts.OnUpdate
    if u then
        u(f, 0.1)
    end
    H.RunTimers(t)
    return xpcall(H.Hekili.Update, debug.traceback)
end

return M
