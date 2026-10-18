-- tests/Forever/style_options_spec.lua (display styles plan, Task 3d): classic's option tabs, built from the shared
-- builders (Options/StyleOptions.lua), equal the dump recorded at the base commit (4f87060d) before the builders
-- existed: every key, order, name, get/set path and function result, under the defaults and with every classic
-- toggle flipped, and classic's defaults. Record with STYLE_OPTIONS=record (rewrites the fixture).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local PATH = "tests/Forever/fixtures/classic_options.lua"

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    assert(headless.cycle(H, H.ctl.now + 0.2))
    return H
end

local function ser(x, seen)
    local t = type(x)
    if t == "string" then
        return ("%q"):format(x)
    elseif t ~= "table" then
        return tostring(x)
    end
    seen = seen or {}
    if seen[x] then
        return "<cycle>"
    end
    seen[x] = true
    local keys = {}
    for k in pairs(x) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. "=" .. ser(x[k], seen)
    end
    seen[x] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function results(ok, ...)
    if not ok then
        return "ERR"
    end
    local n, out = select("#", ...), {}
    for i = 1, n do
        out[i] = ser((select(i, ...)))
    end
    return table.concat(out, ",")
end

-- The path (under the display, or the profile) that holds `sentinel`.
local function find(t, sentinel, prefix, depth)
    for k, v in pairs(t) do
        if v == sentinel then
            return prefix .. tostring(k)
        elseif type(v) == "table" and depth > 0 then
            local p = find(v, sentinel, prefix .. tostring(k) .. ".", depth - 1)
            if p then
                return p
            end
        end
    end
end

local function walk(H, node, path, info, lines)
    local keys = {}
    for k in pairs(node) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
        local v, p = node[k], path .. "." .. tostring(k)
        if k == "args" and type(v) == "table" then
            local child = {}
            for ck, cv in pairs(v) do
                local ci = {}
                for i, s in ipairs(info) do
                    ci[i] = s
                end
                ci[#ci + 1] = ck
                child[ck] = ci
            end
            local ckeys = {}
            for ck in pairs(v) do
                ckeys[#ckeys + 1] = ck
            end
            table.sort(ckeys)
            for _, ck in ipairs(ckeys) do
                walk(H, v[ck], p .. "." .. ck, child[ck], lines)
            end
        elseif type(v) == "function" and k == "set" then
            local old = { pcall(node.get, info) }
            local sentinel = {}
            pcall(v, info, sentinel)
            local profile = H.Hekili.DB.profile
            local at = find(profile.displays.Primary, sentinel, "display.", 4) or find(profile, sentinel, "profile.", 0)
            pcall(v, info, old[2])
            lines[#lines + 1] = p .. " set-> " .. tostring(at)
        elseif type(v) == "function" then
            lines[#lines + 1] = p .. " fn= " .. results(pcall(v, info))
        else
            lines[#lines + 1] = p .. " = " .. ser(v)
        end
    end
end

-- Every boolean of classic's defaults negated, and the strings the option closures test set to another value.
local function flip(H)
    local conf = H.Hekili.DB.profile.displays.Primary.classic
    local function each(def, into)
        for k, v in pairs(def) do
            if type(v) == "boolean" then
                into[k] = not v
            elseif type(v) == "table" and type(into[k]) == "table" and #v == 0 then
                each(v, into[k])
            end
        end
    end
    each(H.ns.UI.Styles.classic.defaults, conf)
    conf.keybindings.separateQueueStyle = true
    conf.delays.desaturate = true
    conf.border.coloring, conf.glow.coloring = "class", "custom"
    conf.delays.type, conf.queue.direction = "TEXT", "TOP"
    conf.primaryWidth, conf.queue.height = 61, 37
end

local function dump()
    local lines = {}
    for _, state in ipairs({ "defaults", "flipped" }) do
        local H = boot()
        if state == "flipped" then
            flip(H)
        end
        H.Hekili.BuildUI = function() end -- the queue setters rebuild; the dump only needs where they write
        H.Hekili:EmbedDisplayOptions()
        local tabs = H.Hekili.Options.args.displays.plugins.Primary.Primary.args.classic.args
        lines[#lines + 1] = "-- " .. state
        if state == "defaults" then -- classic's config template, which the shared defaults now build
            lines[#lines + 1] = "classic.defaults = " .. ser(H.ns.UI.Styles.classic.defaults)
        end
        walk(H, { args = tabs }, "classic", { "displays", "Primary", "classic" }, lines)
        assert.are.same({}, H.errors)
    end
    return lines
end

local function write(lines)
    local f = assert(io.open(PATH, "w"))
    local git = assert(io.popen("git rev-parse --short HEAD"))
    local head = git:read("*l")
    git:close()
    f:write(
        ("-- Generated by tests/Forever/style_options_spec.lua (STYLE_OPTIONS=record) on %s: do not edit.\n"):format(
            head
        )
    )
    f:write("return {\n")
    for _, l in ipairs(lines) do
        f:write(("    %q,\n"):format(l))
    end
    f:write("}\n")
    f:close()
end

describe("classic's option tabs", function()
    it("equal the dump recorded at the base commit, before the shared builders", function()
        local lines = dump()
        if os.getenv("STYLE_OPTIONS") == "record" then
            write(lines)
        end
        local want = dofile(PATH)
        assert.are.equal(#want, #lines)
        for i = 1, #want do
            assert.are.equal(want[i], lines[i])
        end
    end)
end)

-- A registered style whose config holds the shared groups for zones { "now", "next" } and whose options are the
-- shared builders, reached the way an external style reaches them: through Hekili.StyleOptions.
local GROUPS = { "keybindings", "captions", "indicators", "range", "glow", "flash", "border", "targets", "delays" }
local ZONES = { "now", "next" }

local function external(H, groups)
    local SO = H.Hekili.StyleOptions
    return H.Hekili:RegisterDisplayStyle("ext", {
        api = H.Hekili.DisplayStyleAPI,
        label = "External",
        defaults = SO.defaults(groups or GROUPS, ZONES),
        Build = function()
            return {}
        end,
        Draw = function() end,
        Tick = function() end,
        OnGameEvent = function() end,
        Clear = function() end,
        Perimeter = function() end,
        UpdateKeybindings = function() end,
        Options = function(id, conf)
            local tabs = {}
            for i, g in ipairs(groups or GROUPS) do
                tabs[g] = SO[g]("ext", ZONES, i, id, conf)
            end
            return tabs
        end,
    })
end

describe("the shared style option builders", function()
    it("are public as Hekili.StyleOptions and give a later zone its own prefixed blocks", function()
        local H = boot()
        assert.are.equal(H.ns.StyleOptions, H.Hekili.StyleOptions)
        local SO = H.Hekili.StyleOptions
        local conf = { ext = SO.defaults(GROUPS, ZONES) }
        local kb = SO.keybindings("ext", ZONES, 7, "Primary", conf).args
        assert.truthy(kb.nextTextStyle.args.nextFont)
        assert.truthy(kb.nextTextStyle.args.nextColor)
        assert.is_nil(kb.nextLowercase) -- case is shared: the engine honours a zone's only through classic's toggle
        assert.is_nil(kb.nextTextStyle.hidden) -- only classic's queue hides its block behind separateQueueStyle
        assert.is_nil(kb.separateQueueStyle)
        local cap = SO.captions("ext", ZONES, 9, "Primary", conf).args
        assert.truthy(cap.nextPosition.args.nextAnchor)
        assert.are.equal(-100, cap.nextPosition.args.nextX.min)
        assert.truthy(SO.indicators("ext", ZONES, 11, "Primary", conf).args.nextSize.args.nextWidth)
        assert.is_nil(SO.glow("ext", { "now" }, 6, "Primary", conf).args.queued) -- one zone: nothing queued
        assert.are.equal("Now Icon", SO.icon("now", 1, "Primary").name)
        assert.truthy(SO.icon("now", 1, "Primary").args.nowWidth)
        assert.is_nil(SO.border("ext", ZONES, 4, "Primary", conf).args.fit) -- classic's alone
    end)

    it("give a zone named queued the normal per-zone shape unless the zones are marked legacy", function()
        local H = boot()
        local SO = H.Hekili.StyleOptions
        local zones = { "now", "queued" }
        local conf = { ext = SO.defaults(GROUPS, zones) }
        local kb = SO.keybindings("ext", zones, 7, "Primary", conf).args
        assert.is_nil(kb.separateQueueStyle)
        assert.is_nil(kb.queuedTextStyle.hidden)
        assert.is_nil(kb.queuedLowercase)
        assert.truthy(SO.captions("ext", zones, 9, "Primary", conf).args.queuedPosition)
        assert.truthy(SO.indicators("ext", zones, 11, "Primary", conf).args.queuedSize)
        assert.is_nil(conf.ext.keybindings.separateQueueStyle)
        assert.are.equal("BOTTOM", conf.ext.captions.queuedAnchor)
        assert.are.equal(20, conf.ext.indicators.queuedWidth)
    end)

    it("default every zone's fields; classic's queue keeps its legacy queued* fields only", function()
        local H = boot()
        local SO = H.Hekili.StyleOptions
        local d = SO.defaults({ "keybindings", "captions", "indicators" }, ZONES)
        assert.are.same(d.keybindings.color, d.keybindings.nextColor)
        assert.are_not.equal(d.keybindings.color, d.keybindings.nextColor) -- copied, not shared
        assert.is_nil(d.keybindings.nextLowercase)
        assert.are.equal("BOTTOM", d.captions.nextAnchor)
        assert.are.equal(20, d.indicators.nextWidth)
        assert.is_nil(d.keybindings.separateQueueStyle)
        local c = SO.defaults({ "keybindings", "captions" }, { "primary", "queued", legacy = true })
        assert.is_false(c.keybindings.separateQueueStyle)
        assert.is_false(c.keybindings.queuedLowercase)
        assert.are.equal(c.keybindings.font, c.keybindings.queuedFont)
        assert.is_nil(c.captions.queuedAnchor)
        assert.has_error(function()
            SO.defaults({ "nope" }, ZONES)
        end)
    end)

    it("serve an external style's tabs from its own subtable, zone colours included", function()
        local H = boot()
        assert.is_true(external(H))
        local displays = H.Hekili.DB.profile.displays
        H.Hekili:EmbedDisplayOptions()
        local tabs = H.Hekili.Options.args.displays.plugins.Primary.Primary.args.ext.args
        assert.truthy(tabs.range.args.type)
        local path = { "displays", "Primary", "ext", "range", "type" }
        assert.are.equal("ability", H.Hekili:GetDisplayOption(path))
        H.Hekili:SetDisplayOption(path, "melee")
        assert.are.equal("melee", displays.Primary.ext.range.type)
        assert.are.equal("ability", displays.Primary.classic.range.type)
        local color = { "displays", "Primary", "ext", "keybindings", "nextTextStyle", "nextColor", type = "color" }
        H.Hekili:SetDisplayOption(color, 0.5, 0.25, 0, 1)
        assert.are.same({ 0.5, 0.25, 0, 1 }, displays.Primary.ext.keybindings.nextColor)
        assert.are.same({ 0.5, 0.25, 0, 1 }, { H.Hekili:GetDisplayOption(color) })
        assert.are.same({}, H.errors)
    end)
end)

describe("the engine's and the shared resolve's range, flash and keybinding settings", function()
    it("come from the bound style's group, or classic's when the style has none", function()
        local H = boot()
        assert.is_true(external(H, { "range" }))
        local conf = H.Hekili.DB.profile.displays.Primary
        local group = H.Hekili.Engine.StyleGroup
        assert.are.equal(conf.classic.range, group(conf, "range")) -- still classic
        conf.style = "ext"
        assert.are.equal(conf.ext.range, group(conf, "range"))
        assert.are.equal(conf.classic.flash, group(conf, "flash")) -- ext offers no flash
        conf.ext.range.type = "xclude"
        H.Hekili.State.reset("Primary")
        assert.is_true(H.Hekili.State.rangefilter)
        conf.style = "classic"
        H.Hekili.State.reset("Primary")
        assert.is_false(H.Hekili.State.rangefilter)
        assert.are.same({}, H.errors)
    end)

    it("ask LibRangeCheck only while the range check is melee", function()
        local H = boot()
        local LRC = H.env.LibStub("LibRangeCheck-3.0")
        local calls, getRange = 0, LRC.GetRange
        LRC.GetRange = function(...)
            calls = calls + 1
            return getRange(...)
        end
        local d = rawget(H.env, "HekiliDisplayPrimary")
        local conf = H.Hekili.DB.profile.displays.Primary
        local out = H.Hekili.Engine.Output.Primary
        H.ns.UI.Resolve(d, conf, out, H.ctl.now) -- classic's default: per ability
        assert.are.equal(0, calls)
        assert.is_true(external(H, { "range" }))
        conf = H.Hekili.DB.profile.displays.Primary -- AceDB may re-copy it with the new defaults
        conf.style, conf.ext.range.type = "ext", "melee"
        H.ns.UI.Resolve(d, conf, out, H.ctl.now)
        assert.are.equal(1, calls)
        conf.ext.range.enabled = false
        H.ns.UI.Resolve(d, conf, out, H.ctl.now)
        assert.are.equal(1, calls)
        assert.are.same({}, H.errors)
    end)
end)

-- Timeline focus plan, Task 2b: the timeline's options are four tabs (Now, Next, Lane, Timeline) whose keys are not
-- config keys; every option in them reads and writes one field of displays.Primary.timeline, no two the same field.
describe("the timeline's option tabs", function()
    local NOT_OPTIONS = { group = true, description = true, header = true, execute = true }

    -- Every option leaf under `node` as { info path, option type, tab key }.
    local function leaves(node, info, tab, out)
        for k, v in pairs(node.args or {}) do
            local ci = {}
            for i, s in ipairs(info) do
                ci[i] = s
            end
            ci[#ci + 1] = k
            if v.type == "group" then
                leaves(v, ci, tab or k, out)
            elseif not NOT_OPTIONS[v.type] then
                ci.type = v.type
                out[#out + 1] = { info = ci, tab = tab }
            end
        end
        return out
    end

    it("are tab_now, tab_next, tab_lane and tab_timeline, each option resolving to its own timeline field", function()
        local H = boot()
        H.Hekili.BuildUI = function() end
        H.Hekili:EmbedDisplayOptions()
        local group = H.Hekili.Options.args.displays.plugins.Primary.Primary.args.timeline
        local keys = {}
        for k, v in pairs(group.args) do
            keys[#keys + 1] = k
            assert.are.equal("group", v.type, k)
        end
        table.sort(keys)
        assert.are.same({ "tab_lane", "tab_next", "tab_now", "tab_timeline" }, keys)
        assert.are.same({ "Now", "Next", "Lane", "Timeline" }, {
            group.args.tab_now.name,
            group.args.tab_next.name,
            group.args.tab_lane.name,
            group.args.tab_timeline.name,
        })
        local display = H.Hekili.DB.profile.displays.Primary
        for _, k in ipairs(keys) do
            assert.is_nil(display.timeline[k], k) -- a tab key is never a config key
        end

        local where, byTab = {}, {}
        for _, leaf in ipairs(leaves(group, { "displays", "Primary", "timeline" }, nil, {})) do
            local info, option = leaf.info, leaf.info[#leaf.info]
            local old = { H.Hekili:GetDisplayOption(info) }
            local sentinel = {}
            H.Hekili:SetDisplayOption(info, sentinel, 0, 0, 1)
            local at = find(display, sentinel, "display.", 5)
            local path = table.concat(info, ".")
            assert.truthy(at, path)
            if info.type == "color" then
                at = at:gsub("%.1$", "")
            end
            assert.are.equal("display.timeline.", at:sub(1, 17), path)
            assert.are.equal(option, at:match("([^.]+)$"), path)
            assert.are.equal(sentinel, (H.Hekili:GetDisplayOption(info)), path)
            assert.is_nil(where[at], path .. " and " .. tostring(where[at]))
            where[at] = path
            H.Hekili:SetDisplayOption(info, unpack(old))
            byTab[leaf.tab] = byTab[leaf.tab] or {}
            byTab[leaf.tab][at:sub(18)] = true
        end
        local want = {
            tab_now = {
                "nowSize",
                "eta.size",
                "sweep.mode",
                "keybindings.fontSize",
                "glow.highlight",
                "targets.enabled",
                "flash.enabled",
                "border.enabled",
            },
            tab_next = {
                "nextSize",
                "gap",
                "alts.max",
                "keybindings.queued",
                "keybindings.nextFontSize",
                "captions.nextAnchor",
            },
            tab_lane = {
                "laneIconSize",
                "laneEta.enabled",
                "gate.style",
                "keybindings.laneFontSize",
                "indicators.laneWidth",
            },
            tab_timeline = {
                "horizon",
                "pxPerSec",
                "direction",
                "rows",
                "rowGap",
                "laneHeight",
                "rulerStyle",
                "rulerColor",
                "rulerAlphaCombat",
                "rulerAlphaOOC",
                "ruler.ticks",
                "ruler.majorEvery",
                "laneAlpha",
                "laneDim",
                "glide",
                "focusEnabled",
                "focusHorizon",
                "focusColor",
            },
        }
        for tab, list in pairs(want) do
            for _, f in ipairs(list) do
                assert.is_true(byTab[tab][f], tab .. ": " .. f)
            end
        end
        assert.is_nil(where["display.timeline.nextOffset"])
        local n = 0
        for _ in pairs(where) do
            n = n + 1
        end
        assert.is_true(n > 100, tostring(n)) -- every option was walked (126 at Task 2b)
        assert.are.same({}, H.errors)
    end)
end)
