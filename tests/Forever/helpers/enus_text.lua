-- tests/Forever/helpers/enus_text.lua (localization plan, Task 1; spec §8): the English text a player sees, as
-- sorted unique `path<TAB>field<TAB>text` lines: every name, desc and values string of the full options tree, one
-- headless boot per class pack, plus the messages the localization refactor restructured, called with fixed
-- arguments. Written to run unchanged at the merge base 1ef1a63b (before any L[...]) and after the refactor, so the
-- golden it writes at the base proves enUS byte-identical. Reads only the core's public objects and the harness.
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")
local addons = require("helpers.addons")

local M = {}

-- The client's English names of the spells a pack reads at registration (spec §5), from DB2 (wowdb spell <id>).
M.SPELL_NAMES = { [440892] = "Curse of the Elements", [704] = "Curse of Recklessness", [702] = "Curse of Weakness" }

-- [class token] = { client class id, the client's pseudo-spec id } (the class worlds' CLASS_ID and CLIENT_SPEC)
local CLASSES = {
    WARRIOR = { 1, 1491 },
    PALADIN = { 2, 1486 },
    HUNTER = { 3, 1484 },
    ROGUE = { 4, 1488 },
    PRIEST = { 5, 1487 },
    SHAMAN = { 7, 1489 },
    MAGE = { 8, 1485 },
    WARLOCK = { 9, 1490 },
    DRUID = { 11, 1483 },
}

-- One line per text: backslash, line breaks and tabs escaped, and trailing spaces (an editor would trim them).
local function esc(s)
    s = s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t")
    return (s:gsub(" +$", function(sp)
        return ("\\032"):rep(#sp)
    end))
end

-- A headless boot of class token `token` whose client answers M.SPELL_NAMES (fake_api answers "Spell <id>").
local function boot(token)
    local new = fake.new
    fake.new = function(...)
        local api, ctl = new(...)
        local info = api.C_Spell.GetSpellInfo
        api.C_Spell.GetSpellInfo = function(id)
            local i = info(id)
            if i and M.SPELL_NAMES[id] then
                i.name = M.SPELL_NAMES[id]
            end
            return i
        end
        return api, ctl
    end
    local ok, H = pcall(
        headless.new,
        { character = { class = token, classID = CLASSES[token][1], specID = CLASSES[token][2], level = 60 } }
    )
    fake.new = new
    assert(ok, H)
    assert(#H.loadErrors == 0, table.concat(H.loadErrors, "\n"))
    headless.cycle(H, H.ctl.now + 0.2)
    return H
end

-- Every name, desc and values string under `node`, as lines into `out` (a set).
local function walk(node, path, info, out, seen)
    if type(node) ~= "table" or seen[node] then
        return
    end
    seen[node] = true
    local function call(v)
        if type(v) ~= "function" then
            return v
        end
        local ok, r = pcall(v, info)
        return ok and r or nil
    end
    for _, field in ipairs({ "name", "desc" }) do
        local v = call(node[field])
        if type(v) == "string" and v ~= "" then
            out[path .. "\t" .. field .. "\t" .. esc(v)] = true
        end
    end
    local values = call(node.values)
    if type(values) == "table" then
        for k, v in pairs(values) do
            if type(v) == "string" then
                out[path .. "\tvalues." .. tostring(k) .. "\t" .. esc(v)] = true
            end
        end
    end
    local children = {}
    for k, v in pairs(type(node.args) == "table" and node.args or {}) do
        children[k] = v
    end
    for _, group in pairs(type(node.plugins) == "table" and node.plugins or {}) do
        for k, v in pairs(group) do
            children[k] = v
        end
    end
    for k, v in pairs(children) do
        local ci = {}
        for i, s in ipairs(info) do
            ci[i] = s
        end
        ci[#ci + 1] = k
        walk(v, path .. "." .. tostring(k), ci, out, seen)
    end
    seen[node] = nil
end

-- Calls fn(record) with Hekili:Print and Hekili:Notify recorded as `tag<TAB>text` lines.
local function capture(H, tag, out, fn)
    local hk = H.Hekili
    local print, notify = rawget(hk, "Print"), rawget(hk, "Notify")
    local function rec(_, s)
        out["~message\t" .. tag .. "\t" .. esc(tostring(s))] = true
    end
    hk.Print, hk.Notify = rec, rec
    pcall(fn)
    hk.Print, hk.Notify = print, notify
end

-- Engine/Content.lua's notices: a fresh load per case (its once-per-session flag), with a fake client.
local function contentNotices(out)
    local identity = setmetatable({}, {
        __index = function(_, k)
            return k
        end,
    })
    local cases = {
        {
            "shared fails",
            function()
                return false, "MISSING"
            end,
            "WARRIOR",
            "9",
        },
        {
            "shared raises",
            function()
                error("boom", 0)
            end,
            "WARRIOR",
            "9",
        },
        {
            "no class",
            function()
                return true
            end,
            nil,
            "9",
        },
        {
            "no pack",
            function()
                return true
            end,
            "WARRIOR",
            nil,
        },
        {
            "other api",
            function()
                return true
            end,
            "WARRIOR",
            "8",
        },
    }
    local saved = rawget(_G, "Hekili")
    for _, c in ipairs(cases) do
        local ns = {
            L = identity,
            Facade = {
                UnitClass = function()
                    return "Name", c[3], 1
                end,
                C_AddOns = {
                    GetAddOnMetadata = function()
                        return c[4]
                    end,
                    LoadAddOn = c[2],
                },
            },
        }
        _G.Hekili = {
            Notify = function(_, s)
                -- the core's content API is a number, not text: its bump (spec §3) is no English change
                s = s:gsub("this Hekili Forever for %d+;", "this Hekili Forever for <CONTENT_API>;")
                out["~message\tcontent " .. c[1] .. "\t" .. esc(s)] = true
            end,
        }
        assert(loadfile("src/Hekili/Engine/Content.lua"))("Hekili", ns)
        ns.LoadContent()
        ns.ContentNotice()
    end
    _G.Hekili = saved
end

-- Spec.lua's RestoreDefaults notices for `kind` (updated, reverted, retired) at 1, 2 and 3 names.
local function restoreNotices(H, out)
    local hk, class = H.Hekili, H.Hekili.Class
    local p = hk.DB.profile
    local any
    for _, v in pairs(class.packs) do
        any = v
        break
    end
    local packs, retired = class.packs, class.retiredPacks
    for n = 1, 3 do
        local names = { "Alpha", "Beta", "Gamma" }
        for _, kind in ipairs({ "updated", "reverted", "retired" }) do
            local fresh = {}
            class.packs, class.retiredPacks = fresh, {}
            for i = 1, n do
                local name = names[i]
                if kind == "retired" then
                    class.retiredPacks[name] = true
                    p.packs[name] = { builtIn = true, lists = {} }
                else
                    fresh[name] = { version = any.version, import = any.import }
                    p.packs[name] = kind == "reverted" and { version = any.version + 1, builtIn = true, lists = {} }
                        or nil
                end
            end
            capture(H, kind .. " " .. n, out, function()
                hk:RestoreDefaults()
                H.ctl.now = H.ctl.now + 10
                H.RunTimers(H.ctl.now)
            end)
            for i = 1, n do
                p.packs[names[i]] = nil
            end
        end
    end
    class.packs, class.retiredPacks = packs, retired
end

-- The launcher text (UI.lua's GetDataText) for each mode, with and without the minor-cooldowns override.
local function launcher(H, out)
    local p = H.Hekili.DB.profile
    local mm = H.ns.UI.Minimap
    if not mm then
        return
    end
    for _, mode in ipairs({ "automatic", "single", "aoe", "dual", "reactive" }) do
        for _, override in ipairs({ true, false }) do
            p.toggles.mode.value, p.toggles.minor_cooldowns.override = mode, override
            mm:RefreshDataText()
            out["~message\tlauncher " .. mode .. " " .. tostring(override) .. "\t" .. esc(mm.text)] = true
        end
    end
end

M.COMMANDS = {
    "help",
    "bogus",
    "set",
    "set cooldowns",
    "set cooldowns on",
    "set cooldowns off",
    "set mode",
    "set mode aoe",
    "set cycle",
    "set cycle 5",
    "set cycle on",
    "set cycle nope",
    "set spec",
    "set spec nope",
    "set nope",
    "profile",
    "profile Nope",
    "priority",
    "priority Nope",
    "spec",
    "spec nope",
    "disable",
    "enable",
    "lock",
    "unlock",
    "lock",
    "fix",
    "fix toggles",
}

-- Every message the refactor restructured (spec §8), into `out`.
local function messages(H, out)
    for _, cmd in ipairs(M.COMMANDS) do
        capture(H, "/hekili " .. cmd, out, function()
            H.Hekili:CmdLine(cmd)
        end)
    end
    -- every spec setting through /hekili set spec <key>
    for id, spec in pairs(H.Hekili.Engine.Registry.Specs()) do
        if id == H.Hekili.State.spec.id then
            for _, s in ipairs(spec.settings or {}) do
                capture(H, "/hekili set spec " .. s.name, out, function()
                    H.Hekili:CmdLine("set spec " .. s.name)
                end)
            end
        end
    end
    capture(H, "hold", out, function()
        H.Hekili:PlaceHold("potion", true, true)
        H.Hekili:RemoveHold("potion", true)
        H.Hekili:PlaceHold("potion", false, true)
        H.Hekili:RemoveHold("potion", true)
    end)
    capture(H, "build warning", out, function()
        local cur = H.Hekili.CurrentBuild
        H.Hekili.CurrentBuild = 1
        H.Hekili:OnEnable()
        H.Hekili.CurrentBuild = cur
    end)
    capture(H, "cast warnings", out, function()
        local class = H.Hekili.Class
        class.initialized = false
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1)
        class.initialized = true
        local level = H.ctl.level.player
        H.ctl.level.player = 20
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 1)
        H.ctl.level.player = level
    end)
    capture(H, "styles", out, function()
        H.Hekili:RegisterDisplayStyle("enus_test", { api = -1 })
        H.Hekili:RegisterDisplayStyle("queue", { api = H.Hekili.DisplayStyleAPI })
    end)
    capture(H, "unknown style", out, function()
        H.Hekili.DB.profile.displays.Primary.style = "enus_nope"
        H.Hekili:BuildUI()
        H.Hekili.DB.profile.displays.Primary.style = "classic"
    end)
    capture(H, "snapshot", out, function()
        H.Hekili.Engine.settings.screenshot = false -- the harness has no Screenshot()
        H.Hekili:MakeSnapshot()
    end)
    restoreNotices(H, out)
    launcher(H, out)
end

--- The sorted unique lines of every class pack's boot (addons.CONTENT, the shared content first, skipped).
function M.dump()
    local out = {}
    for _, name in ipairs(addons.CONTENT) do
        local token = name:match("^Hekili_(%a+)$"):upper()
        if CLASSES[token] then
            local H = boot(token)
            H.Hekili:RefreshOptions()
            walk(H.Hekili.Options, "options", {}, out, {})
            messages(H, out)
        end
    end
    contentNotices(out)
    local lines = {}
    for l in pairs(out) do
        lines[#lines + 1] = l
    end
    table.sort(lines)
    return lines
end

return M
