-- tests/Forever/display_style_spec.lua (display styles plan, Task 1): what the classic style draws for a fixed
-- 4-record publish into Primary over 3 display frames equals the fixture recorded at the base commit, before the
-- renderer moved out of UI.lua (UI/Styles/Classic.lua). Record with CLASSIC_DRAW=record (rewrites the fixture). The
-- headless stub widgets keep no state, so the spec gives every button region recording Show/Hide, texture, text,
-- point, cooldown, desaturation and vertex colour methods, then rebuilds the UI so Build's anchors are recorded too.
-- Past the draw (Task 2, review M1) the same case records glow state, the tooltip's fields, the overlay-glow and
-- cast-highlight events, a flash pause, the keybinding refresh, the pause overlay, Perimeter and Deactivate's hide;
-- the shims (`d.styleState or d`, `d.style or d`) read the same thing at the base commit and after the extraction.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

-- IsSpellOverlayed answers from this table (fake_api answers false); the classic style reads it at file load.
local overlayed = {}
local fakeNew = fake.new
fake.new = function(...)
    local api, ctl = fakeNew(...)
    api.C_SpellActivationOverlay.IsSpellOverlayed = function(id)
        return overlayed[id] == true
    end
    return api, ctl
end

local PATH = "tests/Forever/fixtures/classic_draw.lua"
local REGIONS = {
    "Texture",
    "Icon",
    "Caption",
    "Keybinding",
    "Cooldown",
    "Highlight",
    "Targets",
    "DelayText",
    "DelayIcon",
    "Overlay",
    "Backdrop",
}

-- Recording widget methods, set on the region itself (rawset) so the harness's shared stubs stay untouched; none
-- allocates once its fields exist.
local rec = {}
function rec.Show(self)
    rawset(self, "__shown", true)
end
function rec.Hide(self)
    rawset(self, "__shown", false)
end
function rec.IsShown(self)
    return rawget(self, "__shown") == true
end
function rec.SetTexture(self, tex)
    rawset(self, "__tex", tex)
end
function rec.GetTexture(self)
    return rawget(self, "__tex")
end
function rec.SetText(self, text)
    rawset(self, "__text", text)
end
function rec.GetText(self)
    return rawget(self, "__text")
end
function rec.ClearAllPoints(self)
    rawset(self, "__point", false)
end
function rec.SetPoint(self, a, rel, b, x, y)
    if type(rel) == "table" then
        rel = rawget(rel, "__name") or "frame"
    end
    rawset(
        self,
        "__point",
        ("%s %s %s %s %s"):format(tostring(a), tostring(rel), tostring(b), tostring(x), tostring(y))
    )
end
function rec.SetCooldown(self, start, duration, modRate)
    rawset(self, "__cdStart", start)
    rawset(self, "__cdDuration", duration)
    rawset(self, "__cdRate", modRate)
end
function rec.SetDesaturated(self, v)
    rawset(self, "__desat", v)
end
function rec.SetVertexColor(self, r, g, b, a)
    rawset(self, "__r", r)
    rawset(self, "__g", g)
    rawset(self, "__b", b)
    rawset(self, "__a", a)
end

local function instrument(f)
    for k, fn in pairs(rec) do
        rawset(f, k, fn)
    end
end

local function boot(saved)
    local H = headless.new({ character = ww.character(), pack = ww.PACK, saved = saved })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    local d = rawget(H.env, "HekiliDisplayPrimary")
    for _, b in ipairs(d.Buttons) do
        instrument(b)
        for _, k in ipairs(REGIONS) do
            if rawget(b, k) then
                instrument(b[k])
            end
        end
    end
    -- past the defaults: captions on every button, the delay countdown, and the delay's desaturation
    local conf = H.Hekili.DB.profile.displays.Primary.classic
    conf.captions.enabled, conf.captions.queued = true, true
    conf.delays.type, conf.delays.desaturate = "TEXT", true
    H.Hekili:BuildUI()
    return H, d
end

-- The fixed set: four Arms abilities with distinct textures, captions, keybinds and times (the first is delayed).
local SET = {
    { "mortal_strike", 1.0, "cycle" },
    { "overpower", 1.5, nil },
    { "slam", 2.0, "cancel" },
    { "rend", 2.5, nil },
}

local function publish(H)
    local abilities = H.Hekili.Engine.Registry.Abilities()
    local now = H.ctl.now
    local s = H.ns.Output.Begin("Primary")
    for i, e in ipairs(SET) do
        local r = s[i]
        r.actionName, r.actionID = e[1], abilities[e[1]].id
        r.texture, r.caption, r.keybind, r.indicator = "tex" .. i, "cap" .. i, "K" .. i, e[3]
        r.time, r.exact_time = e[2], now + e[2]
    end
    H.ns.Output.Publish("Primary", #SET)
end

local function v(x)
    return tostring(x)
end

-- One line per button (all ten), and one per region holding any recorded state.
local function name(t)
    return t and t.actionName
end

local function dump(d, lines)
    lines = lines or {}
    for i, b in ipairs(d.Buttons) do
        lines[#lines + 1] = ("B%d shown=%s point=%s glowing=%s action=%s rec=%s ability=%s exact=%s"):format(
            i,
            v(rawget(b, "__shown")),
            v(rawget(b, "__point")),
            v(b.glowing),
            v(b.Action),
            v(name(b.Recommendation)),
            v(name(b.Ability)),
            v(b.ExactTime)
        )
        for _, k in ipairs(REGIONS) do
            local r = rawget(b, k)
            if r then
                lines[#lines + 1] = ("B%d.%s shown=%s tex=%s text=%s point=%s cd=%s/%s/%s desat=%s vc=%s,%s,%s,%s"):format(
                    i,
                    k,
                    v(rawget(r, "__shown")),
                    v(rawget(r, "__tex")),
                    v(rawget(r, "__text")),
                    v(rawget(r, "__point")),
                    v(rawget(r, "__cdStart")),
                    v(rawget(r, "__cdDuration")),
                    v(rawget(r, "__cdRate")),
                    v(rawget(r, "__desat")),
                    v(rawget(r, "__r")),
                    v(rawget(r, "__g")),
                    v(rawget(r, "__b")),
                    v(rawget(r, "__a"))
                )
            end
        end
    end
    return lines
end

local function write(lines)
    local f = assert(io.open(PATH, "w"))
    local git = assert(io.popen("git rev-parse --short HEAD"))
    local head = git:read("*l")
    git:close()
    f:write(
        ("-- Generated by tests/Forever/display_style_spec.lua (CLASSIC_DRAW=record) on %s: do not edit.\n"):format(
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

-- After the draw: the events a display forwards to its style, the pause overlay, Perimeter, then Deactivate.
local function events(H, d, lines)
    local abilities = H.Hekili.Engine.Registry.Abilities()
    local ms, op = abilities.mortal_strike.id, abilities.overpower.id
    local st = d.styleState or d -- the style's scratch (on the display itself at base)
    overlayed[op], overlayed[ms] = true, nil
    d:OnEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", op)
    d:OnEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", ms)
    H.ctl.current[ms] = true
    d:OnEvent("CURRENT_SPELL_CAST_CHANGED")
    d:OnEvent("ACTIONBAR_SHOWGRID") -- a flash event: pauses SpellFlash
    d:OnEvent("SPELLS_CHANGED") -- a keybinding event
    lines[#lines + 1] = "-- events: flashReady=" .. v(st.flashReady)
    dump(d, lines)
    H.Hekili.Pause = true
    H.ctl.now = H.ctl.now + 0.2
    d.__scripts.OnUpdate(d, 0.2)
    lines[#lines + 1] = "-- paused: paused=" .. v(st.paused)
    dump(d, lines)
    local l, r, t, b
    if d.style then
        l, r, t, b = d.style.Perimeter(d)
    else
        l, r, t, b = d:GetPerimeterButtons()
    end
    lines[#lines + 1] = ("-- perimeter: %s %s %s %s"):format(v(l.__name), v(r.__name), v(t.__name), v(b.__name))
    d:Deactivate()
    for i, btn in ipairs(d.Buttons) do
        lines[#lines + 1] = ("-- deactivated: B%d shown=%s"):format(i, v(rawget(btn, "__shown")))
    end
end

describe("the classic display style", function()
    it("draws a fixed 4-record publish over 3 frames exactly as the base commit's fixture", function()
        local H, d = boot()
        local conf = H.Hekili.DB.profile.displays.Primary.classic
        conf.glow.enabled, conf.glow.queued = true, true
        overlayed[H.Hekili.Engine.Registry.Abilities().mortal_strike.id] = true
        publish(H)
        assert.is_true(d.NewRecommendations)
        local f = d.__scripts.OnUpdate
        for _ = 1, 3 do -- 0.2 s frames: the publish's draw, a frame between pulses, the 0.25 s pulse
            H.ctl.now = H.ctl.now + 0.2
            f(d, 0.2)
        end
        assert.are.same({}, H.errors)
        local lines = dump(d)
        events(H, d, lines)
        assert.are.same({}, H.errors)
        for k in pairs(overlayed) do
            overlayed[k] = nil
        end
        if os.getenv("CLASSIC_DRAW") == "record" then
            write(lines)
        end
        local want = dofile(PATH)
        assert.are.equal(#want, #lines)
        for i, l in ipairs(want) do
            assert.are.equal(l, lines[i], "line " .. i)
        end
    end)

    it("allocates nothing over 1,000 display frames after the first publish", function()
        local H, d = boot()
        publish(H)
        local f = d.__scripts.OnUpdate
        for _ = 1, 3 do
            H.ctl.now = H.ctl.now + 0.2
            f(d, 0.2)
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            f(d, 0.01)
        end
        local bytes = (collectgarbage("count") - before) * 1024
        collectgarbage("restart")
        assert.are.same({}, H.errors)
        assert.are.equal(0, bytes)
    end)
end)

-- Task 2: per-display style selection. A stub style (no buttons, its own `defaults`) registered after boot.
local function stub(H, options)
    local log = { builds = {}, draws = {} }
    H.ns.UI.RegisterStyle("stub", {
        label = "Stub",
        defaults = { foo = 1 },
        Build = function(d)
            log.builds[#log.builds + 1] = d.id
            return {}
        end,
        Draw = function(_, _, out)
            log.draws[#log.draws + 1] = out.count
        end,
        Tick = function() end,
        OnGameEvent = function() end,
        Clear = function() end,
        Perimeter = function() end,
        UpdateKeybindings = function() end,
        Options = function() -- fresh tables per display: core sets each tab's `hidden`
            return options and options()
        end,
    })
    return log
end

local function notifications(H)
    local said = {}
    H.Hekili.Notify = function(_, msg)
        said[#said + 1] = msg
    end
    return said
end

describe("a display's style", function()
    it("takes a style's defaults into every display of a fresh profile", function()
        local H = boot()
        stub(H)
        H.Hekili:GetDefaults()
        H.Hekili.DB:ResetProfile()
        assert.are.equal(1, H.Hekili.DB.profile.displays.Primary.stub.foo)
        assert.are.equal("classic", H.Hekili.DB.profile.displays.Primary.style)
        -- a style group's path is walked through the keys its config has, so an inline section is presentational
        assert.are.equal(1, H.Hekili:GetDisplayOption({ "displays", "Primary", "stub", "sec_now", "foo" }))
        local classic = H.Hekili.DB.profile.displays.Primary.classic
        local font = { "displays", "Primary", "classic", "keybindings", "font" }
        assert.are.equal(classic.keybindings.font, H.Hekili:GetDisplayOption(font))
        H.Hekili:SetDisplayOption({ "displays", "Primary", "classic", "layout", "primaryIcon", "primaryWidth" }, 77)
        assert.are.equal(77, classic.primaryWidth)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "classic", "keybindings", "pos", "x" }, 9)
        assert.are.equal(9, classic.keybindings.x)
    end)

    it(
        "binds classic silently when the profile names no style, and with one Notify when it names an unknown one",
        function()
            local H, d = boot()
            local said = notifications(H)
            local conf = H.Hekili.DB.profile.displays.Primary
            conf.style = nil
            H.Hekili:BuildUI()
            assert.are.equal(H.ns.UI.Styles.classic, d.style)
            assert.are.same({}, said)
            conf.style = "nope"
            H.Hekili:BuildUI()
            assert.are.equal(H.ns.UI.Styles.classic, d.style)
            assert.are.equal(1, #said)
            H.Hekili:BuildUI() -- once per display per unknown name, not on every rebuild
            assert.are.equal(1, #said)
            conf.style = "nope2"
            H.Hekili:BuildUI()
            assert.are.equal(2, #said)
            assert.are.same({}, H.errors)
        end
    )

    it("switching from classic hides every classic button and the new style draws the next publish", function()
        local H, d = boot()
        local log = stub(H)
        publish(H)
        local f = d.__scripts.OnUpdate
        H.ctl.now = H.ctl.now + 0.2
        f(d, 0.2)
        local classic = d.styleFrames.classic
        assert.is_true(classic[1]:IsShown())
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "stub")
        H.Hekili:BuildUI()
        assert.are.equal(H.ns.UI.Styles.stub, d.style)
        for i, b in ipairs(classic) do
            assert.is_false(b:IsShown(), "classic button " .. i)
        end
        assert.are.same({}, H.ns.UI.Buttons.Primary)
        publish(H)
        H.ctl.now = H.ctl.now + 0.2
        f(d, 0.2)
        assert.are.equal(H.Hekili.Engine.Output.Primary.count, log.draws[#log.draws])
        assert.are.equal(4, log.draws[#log.draws])
        assert.are.same({}, H.errors)
    end)

    it("subscribes the display with its style's needs: alts are asked for while it draws the display", function()
        local H, d = boot()
        stub(H)
        H.ns.UI.Styles.stub.needs = { alts = true }
        local out = H.Hekili.Engine.Output.Primary
        assert.are.equal(0, out.needAlts)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "stub")
        H.Hekili:BuildUI()
        d:UpdateAlpha()
        assert.are.equal(1, out.needAlts)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "classic")
        H.Hekili:BuildUI()
        d:UpdateAlpha()
        assert.are.equal(0, out.needAlts)
        assert.are.same({}, H.errors)
    end)

    it("rebuilds, enters and leaves config mode with a display that has no buttons", function()
        local H, d = boot()
        stub(H)
        H.Hekili.DB.profile.displays.Primary.style = "stub"
        H.Hekili:BuildUI()
        assert.are.equal(0, #d.Buttons)
        H.ns.StartConfiguration(true) -- the movers and backdrops; without `true` it also opens the AceConfig dialog,
        -- which fails headless whatever the style (AceConfigDialog.lua:1610)
        H.Hekili.Config = true
        H.Hekili:BuildUI() -- rebuild in config mode: its removed-display pass, then StartConfiguration( true )
        H.Hekili.Config = false
        H.ns.StopConfiguration()
        assert.are.same({}, H.errors)
    end)

    it(
        "offers every style in the dropdown and shows a style's tabs only where it is bound (on Multi, everywhere)",
        function()
            local H = boot()
            stub(H, function()
                return {
                    lane = {
                        type = "group",
                        name = "Lane",
                        args = { sec_now = { type = "group", inline = true, args = {} } },
                    },
                }
            end)
            H.Hekili:EmbedDisplayOptions()
            local plugins = H.Hekili.Options.args.displays.plugins
            local primary, multi = plugins.Primary.Primary.args, plugins.Multi.Multi.args
            local style = primary.main.args.style
            assert.are.same({ classic = "Classic", stub = "Stub", timeline = "Timeline" }, style.values())
            assert.are.same({ "classic", "stub", "timeline" }, style.sorting())
            local function shown(args)
                return {
                    classic = not args.classic.hidden() and args.classic.args.glow ~= nil,
                    stub = not args.stub.hidden(),
                }
            end
            assert.are.same({ classic = true, stub = false }, shown(primary))
            assert.is_nil(primary.main.args.primaryIcon) -- classic's size fields left the core tab
            assert.is_not_nil(primary.classic.args.layout.args.primaryIcon)
            assert.is_not_nil(primary.stub.args.lane.args.sec_now)
            local displays = H.Hekili.DB.profile.displays
            displays.Primary.style = "stub"
            assert.are.same({ classic = false, stub = true }, shown(primary))
            assert.are.same({ classic = false, stub = false }, shown(multi)) -- Multi edits Primary and AOE: they differ
            H.Hekili:SetMultiDisplayOption({ "displays", "Multi", "main", "style" }, "stub")
            assert.are.equal("stub", displays.AOE.style)
            assert.are.same({ classic = false, stub = true }, shown(multi))
            assert.are.same({}, H.errors)
        end
    )

    it("binds a custom display's own style", function()
        local H = boot()
        local log = stub(H)
        H.Hekili:GetDefaults()
        H.Hekili.DB.profile.displays.Custom1.style = "stub"
        H.Hekili:CreateCustomDisplay("Custom1")
        assert.are.same({ "Custom1" }, log.builds)
        assert.are.equal(H.ns.UI.Styles.stub, H.ns.UI.Displays.Custom1.style)
    end)
end)

-- Task 2b: every style under its own subtable. A profile saved before it has classic's fields flat on the display.
local LEGACY = {
    primaryWidth = 61,
    primaryHeight = 62,
    zoom = 11,
    keepAspectRatio = false,
    queue = { width = 33 },
    border = { thickness = 3 },
    range = { type = "melee" },
    glow = { mode = "pixel" },
    flash = { size = 111 },
    captions = { x = 4 },
    indicators = { x = 5 },
    targets = { x = 6 },
    delays = { x = 7 },
    keybindings = { x = 8 },
}

local function legacyProfile()
    local primary = { numIcons = 5, x = 12, style = "classic" }
    for k, val in pairs(LEGACY) do -- a copy: AceDB keeps the saved tables
        if type(val) == "table" then
            local leaf, x = next(val)
            val = { [leaf] = x }
        end
        primary[k] = val
    end
    return { profiles = { Default = { displays = { Primary = primary } } } }
end

describe("classic's settings", function()
    it("move under `classic` on load when a saved profile has them flat; core fields stay", function()
        local H = boot(legacyProfile())
        local conf = H.Hekili.DB.profile.displays.Primary
        for k, val in pairs(LEGACY) do
            assert.is_nil(rawget(conf, k), k)
            if type(val) == "table" then
                local leaf, want = next(val)
                assert.are.equal(want, conf.classic[k][leaf], k .. "." .. leaf)
            else
                assert.are.equal(val, conf.classic[k], k)
            end
        end
        assert.are.equal(50, conf.classic.queue.height) -- the defaults a saved table omitted are kept
        assert.is_true(conf.classic.glow.enabled) -- Primary's own default
        assert.are.equal(5, conf.numIcons)
        assert.are.equal(12, conf.x)
        H.Hekili:RunOneTimeFixes() -- idempotent
        assert.are.equal(61, conf.classic.primaryWidth)
        assert.are.equal(33, conf.classic.queue.width)
        assert.are.same({}, H.errors)
    end)

    it("are left alone in a profile already migrated", function()
        local H = boot({ profiles = { Default = { displays = { Primary = { classic = { primaryWidth = 70 } } } } } })
        local conf = H.Hekili.DB.profile.displays.Primary
        H.Hekili:RunOneTimeFixes()
        assert.are.equal(70, conf.classic.primaryWidth)
        assert.are.equal(50, conf.classic.primaryHeight)
        assert.is_nil(rawget(conf, "primaryWidth"))
    end)

    it("come from the classic style's defaults in a fresh profile", function()
        local H = boot()
        local displays = H.Hekili.DB.profile.displays
        assert.are.same(H.ns.UI.Styles.classic.defaults.keybindings, displays.Primary.classic.keybindings)
        assert.are.equal(50, displays.Primary.classic.primaryWidth)
        assert.are.same({ 0, 1, 0, 1 }, displays.AOE.classic.flash.color) -- a built-in display's own default
        for k in pairs(LEGACY) do
            assert.is_nil(rawget(displays.Primary, k), k)
        end
    end)

    it("keep the rest of `classic` when the recover command restores a built-in display's defaults", function()
        local H = boot()
        local classic = H.Hekili.DB.profile.displays.Primary.classic
        classic.primaryWidth, classic.glow.mode = 70, "pixel"
        H.Hekili:HandleRecoverCommand()
        assert.are.equal(70, classic.primaryWidth)
        assert.are.equal("autocast", classic.glow.mode)
        assert.are.same({}, H.errors)
    end)
end)

-- Task 2c: a style from another addon, through the public door. A dependent addon's files load after Hekili's
-- OnInitialize, so the registration comes after the DB and the first BuildUI.
local function external(H, api)
    local log = { builds = {} }
    local ok = H.Hekili:RegisterDisplayStyle("ext", {
        api = api or H.Hekili.DisplayStyleAPI,
        label = "External",
        defaults = { foo = 1 },
        Build = function(d)
            log.builds[#log.builds + 1] = d.id
            return {}
        end,
        Draw = function() end,
        Tick = function() end,
        OnGameEvent = function() end,
        Clear = function() end,
        Perimeter = function() end,
        UpdateKeybindings = function() end,
        Options = function() end,
    })
    return ok, log
end

local function namesExt()
    return { profiles = { Default = { displays = { Primary = { style = "ext" } } } } }
end

describe("an external display style", function()
    it(
        "registered after boot takes the dropdown, every display's defaults and binds where the profile names it",
        function()
            local H, d = boot(namesExt())
            assert.are.equal(H.ns.UI.Styles.classic, d.style) -- unknown at boot: drawn as classic
            local said = notifications(H)
            local ok, log = external(H)
            assert.is_true(ok)
            local displays = H.Hekili.DB.profile.displays
            assert.are.equal(1, displays.Primary.ext.foo)
            assert.are.equal(1, displays.AOE.ext.foo)
            assert.are.equal("ext", displays.Primary.style)
            H.Hekili:EmbedDisplayOptions()
            local style = H.Hekili.Options.args.displays.plugins.Primary.Primary.args.main.args.style
            assert.are.equal("External", style.values().ext)
            H.RunTimers(H.ctl.now + 1) -- the queued rebuild
            assert.are.equal(H.ns.UI.Styles.ext, d.style)
            assert.are.same({ "Primary" }, log.builds)
            H.Hekili:BuildUI()
            assert.are.same({}, said)
            assert.are.same({}, H.errors)
        end
    )

    it("with another style API version is refused with one Notify and classic stays bound", function()
        local H, d = boot(namesExt())
        local said = notifications(H)
        local ok = external(H, H.Hekili.DisplayStyleAPI + 1)
        assert.is_false(ok)
        assert.are.equal(1, #said)
        assert.truthy(said[1]:find("'ext'", 1, true))
        assert.truthy(said[1]:find(tostring(H.Hekili.DisplayStyleAPI + 1), 1, true))
        assert.truthy(said[1]:find(tostring(H.Hekili.DisplayStyleAPI), 1, true))
        assert.is_nil(H.ns.UI.Styles.ext)
        H.RunTimers(H.ctl.now + 1)
        assert.are.equal(H.ns.UI.Styles.classic, d.style)
        assert.are.same({}, H.errors)
    end)

    it("may not take the name of a core display field or option tab", function()
        local H = boot()
        local said = notifications(H)
        local impl = {}
        for k, val in pairs(H.ns.UI.Styles.classic) do
            impl[k] = val
        end
        for i, taken in ipairs({
            "style",
            "enabled",
            "main",
            "queue",
            "visibility",
            "numIcons",
            "MultiModAOE",
            "glow",
            "primaryWidth",
        }) do
            assert.is_false(H.Hekili:RegisterDisplayStyle(taken, impl), taken)
            assert.are.equal(i, #said, taken)
            assert.is_nil(H.ns.UI.Styles[taken], taken)
        end
        assert.are.equal("classic", H.Hekili.DB.profile.displays.Primary.style)
        assert.are.same({}, H.errors)
    end)
end)

-- Task 4: the timeline style. Its frames are on d.styleFrames.timeline: `widgets` (every frame and region it built)
-- with `labels` naming each for the dump, and `cells` (record i's cell, the list Build returns). Record its fixture with
-- TIMELINE_DRAW=record.
local TL_PATH = "tests/Forever/fixtures/timeline_draw.lua"

-- Recorders for what the timeline sets past classic's (alpha, SetShown), on its widgets only.
local tlrec = {}
for k, fn in pairs(rec) do
    tlrec[k] = fn
end
function tlrec.SetShown(self, on)
    rawset(self, "__shown", on and true or false)
end
function tlrec.SetAlpha(self, a)
    rawset(self, "__alpha", a)
end

local function tlInstrument(T)
    for _, w in ipairs(T.widgets) do
        for k, fn in pairs(tlrec) do
            rawset(w, k, fn)
        end
    end
end

-- Primary bound to the timeline with six icons, its widgets recording unless `plain` (the recorders build strings);
-- the second build records Build's anchors.
local function tlBoot(plain)
    local H, d = boot()
    local conf = H.Hekili.DB.profile.displays.Primary
    conf.style, conf.numIcons = "timeline", 6
    local tl = conf.timeline
    tl.captions.enabled, tl.captions.queued = true, true
    tl.glow.enabled, tl.delays.desaturate = true, true
    tl.laneEta.enabled = true
    H.Hekili:BuildUI()
    local T = d.styleFrames.timeline
    if not plain then
        tlInstrument(T)
    end
    H.Hekili:BuildUI()
    return H, d, T
end

-- Six picks: 1 delayed (now), 2 with two alternatives, 3 short of its resource (the gate), 4 after an idle gap past
-- 3's busy time (a cooldown wait), 5 within rowGap of 4 (row 2), 6 past the horizon (clipped).
local TL_SET = {
    { "mortal_strike", 1.0, "cycle", 30, 40, 1.5 },
    { "overpower", 2.5, nil, 5, 50, 1.5 },
    { "slam", 4.0, "cancel", 15, 10, 1.5 },
    { "rend", 8.0, nil, 10, 20, 1.5 },
    { "whirlwind", 8.3, nil, 25, 30, 1.5 },
    { "sunder_armor", 12.0, nil, 15, 40, 1.5 },
}

local function tlPublish(H)
    local abilities = H.Hekili.Engine.Registry.Abilities()
    local now = H.ctl.now
    local s = H.ns.Output.Begin("Primary")
    local prev = 0
    for i, e in ipairs(TL_SET) do
        local r = s[i]
        r.actionName, r.actionID = e[1], abilities[e[1]].id
        r.texture, r.caption, r.keybind, r.indicator = "tex" .. i, "cap" .. i, "K" .. i, e[3]
        r.time, r.exact_time, r.since = e[2], now + e[2], e[2] - prev
        r.resource_type, r.cost, r.resources.rage, r.busy = "rage", e[4], e[5], e[6]
        prev = e[2]
        r.alts.n = 0
    end
    local a = s[1].alts
    a.n, a[1].actionName, a[1].texture = 1, "slam", "alt1a"
    a = s[2].alts
    a.n, a[1].actionName, a[1].texture, a[2].actionName, a[2].texture = 2, "rend", "alt2a", "whirlwind", "alt2b"
    H.ns.Output.Publish("Primary", #TL_SET)
end

local function tlDump(T, lines)
    lines = lines or {}
    for n, w in ipairs(T.widgets) do
        lines[#lines + 1] = ("%s shown=%s tex=%s text=%s point=%s cd=%s/%s desat=%s vc=%s,%s,%s,%s alpha=%s"):format(
            T.labels[n],
            v(rawget(w, "__shown")),
            v(rawget(w, "__tex")),
            v(rawget(w, "__text")),
            v(rawget(w, "__point")),
            v(rawget(w, "__cdStart")),
            v(rawget(w, "__cdDuration")),
            v(rawget(w, "__desat")),
            v(rawget(w, "__r")),
            v(rawget(w, "__g")),
            v(rawget(w, "__b")),
            v(rawget(w, "__a")),
            v(rawget(w, "__alpha"))
        )
    end
    for i, b in ipairs(T.cells) do
        lines[#lines + 1] = ("cell%d action=%s exact=%s glowing=%s"):format(
            i,
            v(b.Action),
            v(b.ExactTime),
            v(b.glowing)
        )
    end
    return lines
end

local function tlWrite(lines)
    local f = assert(io.open(TL_PATH, "w"))
    local git = assert(io.popen("git rev-parse --short HEAD"))
    local head = git:read("*l")
    git:close()
    f:write(
        ("-- Generated by tests/Forever/display_style_spec.lua (TIMELINE_DRAW=record) on %s: do not edit.\n"):format(
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

describe("the timeline display style", function()
    it("draws a fixed 6-record publish over 3 frames as its recorded fixture", function()
        local H, d, T = tlBoot()
        overlayed[H.Hekili.Engine.Registry.Abilities().mortal_strike.id] = true
        tlPublish(H)
        local f = d.__scripts.OnUpdate
        for _ = 1, 3 do -- the publish's draw, a frame between pulses (lane glides), the 0.25 s pulse
            H.ctl.now = H.ctl.now + 0.2
            f(d, 0.2)
        end
        assert.are.same({}, H.errors)
        local lines = tlDump(T)
        H.Hekili.Pause = true
        H.ctl.now = H.ctl.now + 0.2
        f(d, 0.2)
        lines[#lines + 1] = "-- paused"
        tlDump(T, lines)
        H.Hekili.Pause = false
        local l, r, t, b = d.style.Perimeter(d)
        lines[#lines + 1] = ("-- perimeter: %s %s %s %s"):format(v(l == d), v(r == d), v(t == d), v(b == d))
        d:Deactivate()
        lines[#lines + 1] = "-- deactivated"
        tlDump(T, lines)
        assert.are.same({}, H.errors)
        for k in pairs(overlayed) do
            overlayed[k] = nil
        end
        if os.getenv("TIMELINE_DRAW") == "record" then
            tlWrite(lines)
        end
        local want = dofile(TL_PATH)
        assert.are.equal(#want, #lines)
        for i, l in ipairs(want) do
            assert.are.equal(l, lines[i], "line " .. i)
        end
    end)

    it(
        "places the lane by time: row 2 within rowGap, clipped past the horizon, gate and cooldown-wait marks",
        function()
            local H, d, T = tlBoot()
            tlPublish(H)
            H.ctl.now = H.ctl.now + 0.2
            d.__scripts.OnUpdate(d, 0.2)
            local c = T.cells
            assert.is_true(c[3]:IsShown() and c[4]:IsShown() and c[5]:IsShown())
            assert.is_false(c[6]:IsShown()) -- 12 s: past the 10 s horizon
            assert.are.equal(1, T.row[4])
            assert.are.equal(2, T.row[5]) -- 0.3 s after 4: 7.2 px < rowGap 24
            assert.is_true(c[3].Veil:IsShown()) -- 10 rage short of 15
            assert.is_false(c[4].Veil:IsShown())
            assert.is_true(c[4].Edges[1]:IsShown()) -- idle 8.0 - (4.0 + 1.5) with the rage there
            assert.is_false(c[3].Edges[1]:IsShown())
            assert.is_true(c[2].Alts[2]:IsShown())
            assert.are.equal("alt2b", c[2].Alts[2]:GetTexture())
            assert.is_false(c[1].Alts[2]:IsShown())
            assert.are.same({}, H.errors)
        end
    )

    it("allocates nothing over 1,000 display frames after the first publish, on a moving clock", function()
        local H, d = tlBoot(true)
        tlPublish(H)
        local f = d.__scripts.OnUpdate
        for _ = 1, 3 do
            H.ctl.now = H.ctl.now + 0.2
            f(d, 0.2)
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            H.ctl.now = H.ctl.now + 0.01
            f(d, 0.01)
        end
        local bytes = (collectgarbage("count") - before) * 1024
        collectgarbage("restart")
        assert.are.same({}, H.errors)
        assert.are.equal(0, bytes)
    end)

    it("switching classic -> timeline -> classic hides every widget of the style left", function()
        local H, d = boot()
        publish(H)
        local f = d.__scripts.OnUpdate
        H.ctl.now = H.ctl.now + 0.2
        f(d, 0.2)
        local classic = d.styleFrames.classic
        assert.is_true(classic[1]:IsShown())
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "timeline")
        H.Hekili:BuildUI()
        assert.are.equal(H.ns.UI.Styles.timeline, d.style)
        for i, b in ipairs(classic) do
            assert.is_false(b:IsShown(), "classic button " .. i)
        end
        local T = d.styleFrames.timeline
        assert.are.equal(T.cells, d.Buttons)
        tlInstrument(T)
        H.Hekili:BuildUI()
        tlPublish(H)
        H.ctl.now = H.ctl.now + 0.2
        f(d, 0.2)
        assert.is_true(T.cells[1]:IsShown())
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "classic")
        H.Hekili:BuildUI()
        assert.are.equal(H.ns.UI.Styles.classic, d.style)
        for n, w in ipairs(T.widgets) do
            assert.is_false(w:IsShown(), T.labels[n])
        end
        assert.are.same({}, H.errors)
    end)

    it("shows its cells and ruler again on the first publish after its alpha went to 0 and back", function()
        local H, d, T = tlBoot()
        tlPublish(H)
        local f = d.__scripts.OnUpdate
        H.ctl.now = H.ctl.now + 0.2
        f(d, 0.2)
        local c1 = T.cells[1]
        assert.is_true(c1.Texture:IsShown() and T.base:IsShown())
        H.Hekili.Barber = true -- alpha 0: core unsubscribes and clears the style
        d:UpdateAlpha()
        assert.is_false(c1.Texture:IsShown())
        assert.is_false(T.base:IsShown())
        H.Hekili.Barber = nil
        d:UpdateAlpha()
        tlPublish(H)
        H.ctl.now = H.ctl.now + 0.2
        f(d, 0.2)
        assert.is_true(c1:IsShown())
        assert.is_true(c1.Texture:IsShown())
        assert.is_true(c1.Top:IsShown())
        assert.is_true(c1.Eta:IsShown())
        assert.is_true(T.base:IsShown())
        assert.is_true(T.ticks[1]:IsShown())
        assert.is_false(T.ticks[12]:IsShown()) -- past the 10 s horizon
        assert.are.same({}, H.errors)
    end)

    it("asks the engine for alternatives while it draws a display", function()
        local H, d = boot()
        local out = H.Hekili.Engine.Output.Primary
        assert.are.equal(0, out.needAlts)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "timeline")
        H.Hekili:BuildUI()
        d:UpdateAlpha()
        assert.are.equal(1, out.needAlts)
    end)

    it("defaults every display's timeline subtable and serves its options from it", function()
        local H = boot()
        local tl = H.Hekili.DB.profile.displays.Primary.timeline
        assert.are.equal(10, tl.horizon)
        assert.are.equal(24, tl.pxPerSec)
        assert.are.equal("RIGHT", tl.direction)
        assert.are.equal(16, tl.eta.size)
        assert.are.equal("extend", tl.sweep.mode)
        assert.are.equal("veil", tl.gate.style)
        assert.is_true(tl.alts.enabled)
        assert.are.equal("both", tl.alts.zones)
        assert.are.equal(12, tl.keybindings.laneFontSize) -- the shared groups' lane zone
        local get = function(path)
            return H.Hekili:GetDisplayOption(path)
        end
        assert.are.equal(false, get({ "displays", "Primary", "timeline", "glow", "enabled" }))
        assert.are.equal(12, get({ "displays", "Primary", "timeline", "keybindings", "nextFontSize" }))
        assert.are.equal(16, get({ "displays", "Primary", "timeline", "layout", "sec_now", "eta", "size" }))
        assert.are.equal(2, get({ "displays", "Primary", "timeline", "layout", "sec_alts", "alts", "max" }))
        H.Hekili:SetDisplayOption({ "displays", "Primary", "timeline", "layout", "sec_lane", "horizon" }, 8)
        assert.are.equal(8, tl.horizon)
        H.Hekili:EmbedDisplayOptions()
        local args = H.Hekili.Options.args.displays.plugins.Primary.Primary.args.timeline.args
        local layout = args.layout.args
        for _, k in ipairs({ "sec_now", "sec_next", "sec_lane", "sec_alts" }) do
            assert.truthy(layout[k], k)
            assert.is_true(layout[k].inline, k)
            assert.is_nil(tl[k], k) -- presentational, not a config key
        end
        for _, k in ipairs({
            "keybindings",
            "border",
            "range",
            "glow",
            "flash",
            "captions",
            "targets",
            "delays",
            "indicators",
        }) do
            assert.truthy(args[k], k)
        end
        assert.is_true(args.layout.order < args.border.order)
        assert.are.same({}, H.errors)
    end)
end)
