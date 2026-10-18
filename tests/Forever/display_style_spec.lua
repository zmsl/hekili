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
-- the second build records Build's anchors. `setup( tl )` changes the config before it; `saved` is the saved profile.
local function tlBoot(plain, setup, saved)
    local H, d = boot(saved)
    local conf = H.Hekili.DB.profile.displays.Primary
    conf.style, conf.numIcons = "timeline", 6
    local tl = conf.timeline
    tl.captions.enabled, tl.captions.queued = true, true
    tl.glow.enabled, tl.delays.desaturate = true, true
    tl.laneEta.enabled = true
    tl.oocPinned = false -- the wall clock the fixture and the tests before Task 2c expect (status.combat is false)
    tl.nowFallback = "press" -- the layout before the empty now circle (the fixture's); its own tests set "empty"
    if setup then
        setup(tl)
    end
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

-- `focus`: the record flagged as a focus candidate (the APL entry's focus=1), if any.
-- `edit( s )` changes the records before the publish.
local function tlPublish(H, focus, edit)
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
    if focus then
        s[focus].focus = 1
    end
    if edit then
        edit(s)
    end
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
        -- today's layout, a focus record in the now circle, then pinned out of combat (Task 2c), the empty now circle
        for _, case in ipairs({ { false }, { 3 }, { false, true }, { false, false, "empty" } }) do
            local focus = case[1]
            local H, d = tlBoot(true, function(tl)
                tl.oocPinned = case[2] or false
                tl.nowFallback = case[3] or "press"
            end)
            tlPublish(H, focus or nil)
            local f = d.__scripts.OnUpdate
            for _ = 1, 3 do
                H.ctl.now = H.ctl.now + 0.2
                f(d, 0.2)
            end
            local want = not case[3] and (focus and "slam" or "mortal_strike")
            assert.are.equal(want, d.styleFrames.timeline.cells[1].Action or false)
            collectgarbage("collect")
            collectgarbage("stop")
            local status = H.Hekili.Engine.Output.status
            local before = collectgarbage("count")
            for n = 1, 1000 do
                if n % 250 == 0 then
                    status.combat = not status.combat -- the ruler's alpha switches on a flip
                end
                H.ctl.now = H.ctl.now + 0.01
                f(d, 0.01)
            end
            local bytes = (collectgarbage("count") - before) * 1024
            collectgarbage("restart")
            status.combat = false
            assert.are.same({}, H.errors)
            assert.are.equal(0, bytes, tostring(focus))
        end
    end)

    -- Task 2 (timeline focus): the zone rule. Record 3 (slam, 4 s) flagged within the focus horizon takes the now
    -- circle with its ETA, no keybind and the gold ring; record 1 (mortal_strike) moves to the next box with every
    -- press affordance; the lane draws records 2, 4.. (never 3).
    local function tlFrame(H, d)
        H.ctl.now = H.ctl.now + 0.2
        d.__scripts.OnUpdate(d, 0.2)
    end

    local function actions(T)
        local list = {}
        for i, b in ipairs(T.cells) do
            list[i] = b.Action or false
        end
        return list
    end

    local TODAY =
        { "mortal_strike", "overpower", "slam", "rend", "whirlwind", "sunder_armor", false, false, false, false }
    local FOCUS3 =
        { "slam", "mortal_strike", "overpower", "rend", "whirlwind", "sunder_armor", false, false, false, false }

    it("draws a flagged record within the focus horizon in the now circle and the press in the next box", function()
        local H, d, T = tlBoot()
        local abilities = H.Hekili.Engine.Registry.Abilities()
        local ms, slam = abilities.mortal_strike, abilities.slam
        overlayed[ms.id] = true -- record 1 glows; glow.queued is off, so only its cell may
        H.ctl.usable[ms.actualName or ms.name] = { false, true } -- record 1 unusable: its cell tints grey
        local flashed = {}
        local flash = H.ns.UI.FlashRecommendation
        H.ns.UI.FlashRecommendation = function(st, conf, a, elapsed)
            flashed[#flashed + 1] = a
            return flash(st, conf, a, elapsed)
        end
        H.Hekili.Engine.Output.status.numTargets = 3 -- a target count to show
        tlPublish(H, 3)
        tlFrame(H, d)
        tlFrame(H, d) -- Tick (the ETAs) runs before Draw: the publish's ETAs show on the frame after
        local c = T.cells
        assert.are.same(FOCUS3, actions(T))
        assert.is_true(c[1]:IsShown() and c[2]:IsShown())
        -- the now circle: the focus record, its countdown, no keybind, the ring
        assert.are.equal("tex3", c[1].Texture:GetTexture())
        assert.are.equal("3.6", c[1].Eta:GetText()) -- slam at 4 s, 0.4 s on
        assert.is_nil(c[1].Keybinding:GetText())
        assert.is_true(c[1].Ring:IsShown())
        assert.is_false(c[1].glowing)
        assert.are.equal(1, rawget(c[1].Texture, "__r")) -- slam usable
        assert.is_nil(c[1].Targets:GetText())
        assert.is_false(c[1].Alts[1]:IsShown())
        -- the next box: the press record with its keybind, glow, tint, target count, alternatives and flash
        assert.are.equal("tex1", c[2].Texture:GetTexture())
        assert.are.equal("K1", c[2].Keybinding:GetText())
        assert.is_true(c[2].glowing)
        assert.are.equal(0.4, rawget(c[2].Texture, "__r"))
        assert.are.equal("3|r", c[2].Targets:GetText())
        assert.is_true(c[2].Alts[1]:IsShown())
        assert.are.equal("alt1a", c[2].Alts[1]:GetTexture())
        assert.are.equal("mortal_strike", flashed[#flashed])
        -- the lane: records 2, 4, 5, 6
        assert.are.equal("tex2", c[3].Texture:GetTexture())
        assert.are.equal("tex4", c[4].Texture:GetTexture())
        -- the overlay glow and the cast highlight follow the press record's cell
        d:OnEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", ms.id)
        assert.is_false(c[2].glowing)
        d:OnEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", ms.id)
        assert.is_true(c[2].glowing)
        assert.is_false(c[1].glowing)
        d:OnEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", slam.id)
        assert.is_false(c[1].glowing) -- not the press, glow.queued off
        H.ctl.current[ms.id] = true
        d:OnEvent("CURRENT_SPELL_CAST_CHANGED")
        assert.is_true(c[2].Highlight:IsShown())
        assert.is_false(c[1].Highlight:IsShown())
        d.style.UpdateKeybindings(d)
        assert.is_nil(c[1].Keybinding:GetText())
        assert.truthy(c[2].Keybinding:GetText())

        -- unflagged again: today's layout, the press affordances back on cell 1
        tlPublish(H)
        tlFrame(H, d)
        assert.are.same(TODAY, actions(T))
        assert.is_false(c[1].Ring:IsShown())
        assert.are.equal("K1", c[1].Keybinding:GetText())
        assert.is_true(c[1].glowing)
        assert.is_false(c[2].glowing)
        assert.is_nil(c[2].Targets:GetText())
        assert.are.equal("3|r", c[1].Targets:GetText())
        assert.is_false(c[2].Highlight:IsShown())
        assert.are.equal("mortal_strike", flashed[#flashed])
        H.ns.UI.FlashRecommendation = flash
        overlayed[ms.id] = nil
        assert.are.same({}, H.errors)
    end)

    local EMPTY =
        { false, "mortal_strike", "overpower", "slam", "rend", "whirlwind", "sunder_armor", false, false, false }

    it("leaves the now circle empty without a focus record (nowFallback empty, the default)", function()
        local H, d, T = tlBoot(false, function(tl)
            tl.nowFallback = "empty"
        end)
        local ms = H.Hekili.Engine.Registry.Abilities().mortal_strike
        overlayed[ms.id] = true
        H.Hekili.Engine.Output.status.numTargets = 3
        tlPublish(H)
        tlFrame(H, d)
        tlFrame(H, d)
        local c = T.cells
        assert.are.same(EMPTY, actions(T))
        -- the now circle: nothing
        assert.is_false(c[1]:IsShown())
        assert.is_nil(c[1].Texture:GetTexture())
        assert.is_nil(c[1].Keybinding:GetText())
        assert.is_false(c[1].Ring:IsShown())
        assert.is_false(c[1].glowing)
        assert.is_nil(c[1].Recommendation)
        -- the next box: the press with every press affordance
        assert.is_true(c[2]:IsShown())
        assert.are.equal("tex1", c[2].Texture:GetTexture())
        assert.are.equal("K1", c[2].Keybinding:GetText())
        assert.is_true(c[2].glowing)
        assert.are.equal("3|r", c[2].Targets:GetText())
        assert.is_true(c[2].Alts[1]:IsShown())
        assert.are.equal("alt1a", c[2].Alts[1]:GetTexture())
        assert.are.equal("0.6", c[2].Eta:GetText()) -- mortal_strike at 1 s, 0.4 s on
        -- the extend sweep follows the press: cell 2's runs until record 1's time, cell 1 has none
        local cd = c[2].Cooldown
        assert.are.equal(c[2].ExactTime - rawget(cd, "__cdStart"), rawget(cd, "__cdDuration"))
        assert.is_nil(rawget(c[1].Cooldown, "__cdDuration"))
        -- the lane: records 2..
        assert.are.equal("tex2", c[3].Texture:GetTexture())
        assert.are.equal("tex3", c[4].Texture:GetTexture())
        d.style.UpdateKeybindings(d)
        assert.is_nil(c[1].Keybinding:GetText())
        assert.truthy(c[2].Keybinding:GetText())
        -- a focus record: the now circle takes it as before
        tlPublish(H, 3)
        tlFrame(H, d)
        assert.are.same(FOCUS3, actions(T))
        assert.is_true(c[1]:IsShown() and c[1].Ring:IsShown())
        assert.is_nil(c[1].Keybinding:GetText())
        assert.are.equal("K1", c[2].Keybinding:GetText())
        -- gone again: empty
        tlPublish(H)
        tlFrame(H, d)
        assert.are.same(EMPTY, actions(T))
        assert.is_false(c[1]:IsShown() or c[1].Ring:IsShown())
        assert.is_true(c[2].glowing)
        -- the pause overlay is a press affordance: on the next box here
        H.Hekili.Pause = true
        tlFrame(H, d)
        assert.is_true(c[2].Overlay:IsShown())
        assert.is_false(c[1].Overlay:IsShown())
        H.Hekili.Pause = false
        tlFrame(H, d)
        assert.is_false(c[2].Overlay:IsShown())
        -- config mode: the mover's backdrop spans the display frame, the empty circle included
        H.ns.StartConfiguration(true)
        local tl = H.Hekili.DB.profile.displays.Primary.timeline
        local l, r = d.style.Perimeter(d)
        assert.is_true(l == d and r == d)
        assert.are.equal(tl.nowSize + tl.gap + tl.nextSize + tl.gap, T.laneX0)
        H.ns.StopConfiguration()
        -- "press" on the live display: the earlier layout
        tl.nowFallback = "press"
        tlPublish(H)
        tlFrame(H, d)
        assert.are.same(TODAY, actions(T))
        assert.is_true(c[1]:IsShown())
        overlayed[ms.id] = nil
        assert.are.same({}, H.errors)
    end)

    it("keeps today's layout with focus off, a flagged record 1, or a flag past the focus horizon", function()
        local H, d, T = tlBoot()
        local tl = H.Hekili.DB.profile.displays.Primary.timeline
        assert.is_true(tl.focusEnabled)
        assert.are.equal(10, tl.focusHorizon)
        assert.are.same({ 1, 0.8, 0.1, 1 }, tl.focusColor)
        tl.focusEnabled = false
        tlPublish(H, 3)
        tlFrame(H, d)
        assert.are.same(TODAY, actions(T))
        assert.is_false(T.cells[1].Ring:IsShown())
        assert.are.equal("K1", T.cells[1].Keybinding:GetText())
        tl.focusEnabled = true
        tlPublish(H, 1) -- record 1 never counts
        tlFrame(H, d)
        assert.are.same(TODAY, actions(T))
        tl.focusHorizon = 3 -- slam is 4 s out
        tlPublish(H, 3)
        tlFrame(H, d)
        assert.are.same(TODAY, actions(T))
        tl.focusHorizon = 20 -- clamped to the 10 s lane horizon: sunder_armor at 12 s does not count
        tlPublish(H, 6)
        tlFrame(H, d)
        assert.are.same(TODAY, actions(T))
        tlPublish(H, 5) -- whirlwind at 8.3 s does
        tlFrame(H, d)
        assert.are.equal("whirlwind", T.cells[1].Action)
        assert.are.equal("mortal_strike", T.cells[2].Action)
        tlPublish(H, nil, function(s)
            s[3].focus = 0 -- focus=0 in hand-written SimC is off
        end)
        tlFrame(H, d)
        assert.are.same(TODAY, actions(T))
        assert.are.same({}, H.errors)
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
        assert.is_true(T.cells[2]:IsShown()) -- the press (the now circle is empty by default)
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

    it("asks for alternatives only while the display shows them", function()
        local H, d = boot()
        local out = H.Hekili.Engine.Output.Primary
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "timeline")
        H.Hekili:BuildUI()
        H.Hekili.DB.profile.displays.Primary.timeline.alts.enabled = false
        d:UpdateAlpha()
        assert.are.equal(0, out.needAlts)
        H.Hekili.DB.profile.displays.Primary.timeline.alts.enabled = true
        d:UpdateAlpha()
        assert.are.equal(1, out.needAlts)
        assert.are.same({}, H.errors)
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
        assert.are.equal(16, get({ "displays", "Primary", "timeline", "tab_now", "eta", "size" }))
        assert.are.equal(2, get({ "displays", "Primary", "timeline", "tab_next", "alts", "max" }))
        H.Hekili:SetDisplayOption({ "displays", "Primary", "timeline", "tab_timeline", "sec_lane", "horizon" }, 8)
        assert.are.equal(8, tl.horizon)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "timeline", "tab_timeline", "sec_focus", "focusHorizon" }, 6)
        assert.are.equal(6, tl.focusHorizon)
        assert.are.equal("empty", tl.nowFallback)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "timeline", "tab_now", "nowFallback" }, "press")
        assert.are.equal("press", tl.nowFallback)
        H.Hekili:EmbedDisplayOptions()
        local tabs = H.Hekili.Options.args.displays.plugins.Primary.Primary.args.timeline.args
        assert.is_true(tabs.tab_timeline.args.sec_focus.inline) -- Task 2's Focus section, in the Timeline tab
        local now = tabs.tab_now.args
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
            assert.is_true(now[k].inline, k) -- the shared groups' now zone, after the zone's layout
            assert.is_true(now.nowSize.order < now[k].order, k)
        end
        assert.are.same({}, H.errors)
    end)
end)

-- Timeline focus plan, Task 2b: the ruler styles, equal gaps and the ruler's alpha on a combat flip.
-- A region's anchor (x, y) in config pixels from the display's start corner (place: x * scale, -y * scale).
local function anchor(H, region)
    local x, y = rawget(region, "__point"):match("(%S+) (%S+)$")
    local s = H.Hekili:GetScale()
    return tonumber(x) / s, -tonumber(y) / s
end

local function near(want, got, what)
    assert.is_true(math.abs(want - got) < 1e-6, ("%s: want %s, got %s"):format(what, tostring(want), tostring(got)))
end

-- The ruler's pool: base and ticks, shown count. The defaults put t = 0 at 48 + 12 + 48 + 12 = 120, the rows' top at
-- 56 - 2 * 20 = 16 (the ruler's baseline 7 above it, at 9), 24 px a second, 11 ticks for the 10 s horizon.
local function shownMarks(T)
    local n = T.base:IsShown() and 1 or 0
    for k = 1, #T.ticks do
        n = n + (T.ticks[k]:IsShown() and 1 or 0)
    end
    return n
end

local RULERS = {
    ruler = { shown = 12, base = { 120, 9 }, tick1 = { 120, 3 }, tick2 = { 144, 6 } }, -- a major tick at 0 s
    dots = { shown = 11, tick1 = { 120, 7 }, tick2 = { 144, 7 } },
    lines = { shown = 11, tick1 = { 120, 5 }, tick2 = { 144, 5 } },
    center = { shown = 1, base = { 120, 36 } }, -- through the middle of the two rows (16 .. 56)
}

for _, style in ipairs({ "ruler", "dots", "lines", "center" }) do
    describe("the timeline's " .. style .. " ruler", function()
        it("draws its marks from the one pool, the first at the lane's t = 0", function()
            local H, d, T = tlBoot(false, function(tl)
                tl.rulerStyle = style
            end)
            tlPublish(H)
            H.ctl.now = H.ctl.now + 0.2
            d.__scripts.OnUpdate(d, 0.2)
            local want = RULERS[style]
            assert.are.equal(want.shown, shownMarks(T))
            assert.are.equal(want.base ~= nil, T.base:IsShown())
            assert.are.equal(want.tick1 ~= nil, T.ticks[1]:IsShown())
            assert.is_false(T.ticks[12]:IsShown()) -- past the horizon
            for _, k in ipairs({ "base", "tick1", "tick2" }) do
                if want[k] then
                    local x, y = anchor(H, k == "base" and T.base or T.ticks[k == "tick1" and 1 or 2])
                    near(want[k][1], x, style .. " " .. k .. " x")
                    near(want[k][2], y, style .. " " .. k .. " y")
                end
            end
            assert.are.same({}, H.errors)
        end)
    end)
end

describe("the timeline's gaps", function()
    it("are one gap from the now circle to the next box and from the next box to the lane", function()
        for _, case in ipairs({ { 48, 48, 12 }, { 40, 56, 20 } }) do
            local H, _, T = tlBoot(false, function(tl)
                tl.nowSize, tl.nextSize, tl.gap = case[1], case[2], case[3]
            end)
            local x1 = anchor(H, T.cells[1])
            local x2 = anchor(H, T.cells[2])
            local x0 = anchor(H, T.ticks[1]) -- the ruler's first mark: the lane's t = 0
            near(case[3], x2 - (x1 + case[1]), "now -> next")
            near(case[3], x0 - (x2 + case[2]), "next -> lane")
            near(x0, T.laneX0, "laneX0")
            assert.are.same({}, H.errors)
        end
    end)

    it("come from a saved profile's nextOffset once, the cells where they were", function()
        local saved =
            { profiles = { Default = { displays = { Primary = { timeline = { nextOffset = 70, nowSize = 50 } } } } } }
        local H, _, T = tlBoot(false, nil, saved)
        local tl = H.Hekili.DB.profile.displays.Primary.timeline
        assert.is_nil(rawget(tl, "nextOffset"))
        assert.are.equal(20, tl.gap)
        -- where the base commit's Build put them: the circle at 0, the box at nextOffset, both centred in the band
        local band = math.max(50, 48, 56)
        local x1, y1 = anchor(H, T.cells[1])
        local x2, y2 = anchor(H, T.cells[2])
        near(0, x1, "now x")
        near((band - 50) / 2, y1, "now y")
        near(70, x2, "next x")
        near((band - 48) / 2, y2, "next y")
        H.Hekili:RunOneTimeFixes() -- once: nothing left to derive from
        assert.are.equal(20, tl.gap)
        assert.are.same({}, H.errors)
    end)
end)

describe("the timeline's ruler alpha", function()
    it("switches between its combat and out-of-combat values when status.combat flips, in Draw only", function()
        local H, d, T = tlBoot()
        local status = H.Hekili.Engine.Output.status
        local sets, setAlpha = 0, rawget(T.base, "SetAlpha")
        rawset(T.base, "SetAlpha", function(self, a)
            sets = sets + 1
            return setAlpha(self, a)
        end)
        status.combat = false
        tlPublish(H)
        local f = d.__scripts.OnUpdate
        for _ = 1, 3 do
            H.ctl.now = H.ctl.now + 0.2
            f(d, 0.2)
        end
        assert.are.equal(0.25, rawget(T.base, "__alpha"))
        assert.are.equal(0.25, rawget(T.ticks[1], "__alpha"))
        assert.are.equal(1, sets)
        for _ = 1, 30 do -- frames and pulses with no flip set nothing
            H.ctl.now = H.ctl.now + 0.05
            f(d, 0.05)
        end
        assert.are.equal(1, sets)
        status.combat = true
        for _ = 1, 3 do
            H.ctl.now = H.ctl.now + 0.2
            f(d, 0.2)
        end
        assert.are.equal(0.5, rawget(T.base, "__alpha"))
        assert.are.equal(0.5, rawget(T.ticks[11], "__alpha"))
        assert.are.equal(2, sets)
        status.combat = false
        H.ctl.now = H.ctl.now + 0.3
        f(d, 0.3)
        assert.are.equal(0.25, rawget(T.base, "__alpha"))
        assert.are.equal(3, sets)
        assert.are.same({}, H.errors)
    end)
end)

-- Timeline focus plan, Task 2c: the lane never left of laneX0; out of combat (oocPinned) the lane and the ETAs on the
-- press-relative times (rec.time - recs[ 1 ].time), still between publishes.
describe("the timeline's out-of-combat pinning", function()
    local function laneXs(H, T)
        local xs = {}
        for c = 3, 5 do
            xs[c] = anchor(H, T.cells[c])
        end
        return xs
    end

    -- Four publishes 0.2 s apart (each set's exact_times 0.2 s later, its time offsets unchanged), three frames between;
    -- `shift`: every record's time also 0.2 s earlier per publish (the press-relative times unchanged).
    local function run(combat, shift)
        local H, d, T = tlBoot(false, function(tl)
            tl.oocPinned = true
        end)
        local status = H.Hekili.Engine.Output.status
        status.combat = combat
        local seen = {}
        for n = 1, 4 do
            tlPublish(H, nil, shift and function(s)
                for i = 1, #TL_SET do
                    s[i].time = s[i].time - 0.2 * n
                end
            end)
            for _ = 1, 3 do
                H.ctl.now = H.ctl.now + 0.05
                d.__scripts.OnUpdate(d, 0.05)
                seen[#seen + 1] = laneXs(H, T)
            end
            H.ctl.now = H.ctl.now + 0.05
        end
        status.combat = false
        assert.are.same({}, H.errors)
        return seen, T
    end

    it("holds the lane and the ETAs still between publishes out of combat", function()
        local seen, T = run(false)
        for n = 2, #seen do
            assert.are.same(seen[1], seen[n], "frame " .. n)
        end
        -- pick 3 (slam) 3 s after the press: 120 + 3 * 24 - 10
        near(T.laneX0 + 3 * 24 - 10, seen[1][3], "slam")
        assert.are.equal("", T.cells[1].Eta:GetText()) -- the press: 0 when pinned
        assert.are.equal("1.5", T.cells[2].Eta:GetText()) -- overpower 1.5 s after it
        assert.are.equal("3.0", T.cells[3].Eta:GetText())
    end)

    it(
        "holds the lane still when every time shifts by 0.2 s per publish, the offsets between them unchanged",
        function()
            local seen = run(false, true)
            for n = 2, #seen do
                assert.are.same(seen[1], seen[n], "frame " .. n)
            end
        end
    )

    it("moves with the clock in combat", function()
        local seen = run(true)
        assert.is_true(seen[2][3] < seen[1][3])
        assert.is_true(seen[3][3] < seen[2][3])
    end)

    it("anchors a pick before the press at laneX0 and hides one past the horizon", function()
        for _, combat in ipairs({ false, true }) do
            local H, d, T = tlBoot(false, function(tl)
                tl.oocPinned, tl.glide = true, 0
            end)
            local status = H.Hekili.Engine.Output.status
            status.combat = combat
            tlPublish(H, nil, function(s)
                s[3].time, s[3].exact_time = 0.5, s[3].exact_time - 3.5 - (combat and 1 or 0) -- before the press
            end)
            H.ctl.now = H.ctl.now + 0.2
            d.__scripts.OnUpdate(d, 0.2)
            near(T.laneX0 - 10, anchor(H, T.cells[3]), "past pick " .. tostring(combat))
            assert.is_true(T.cells[3]:IsShown())
            assert.is_false(T.cells[6]:IsShown()) -- 11 s after the press, 11.8 s on the clock: past the 10 s horizon
            status.combat = false
            assert.are.same({}, H.errors)
        end
    end)

    it("pins the focus zone too: a flag within the horizon by press-relative time takes the now circle", function()
        local H, d, T = tlBoot(false, function(tl)
            tl.oocPinned, tl.focusHorizon = true, 7.5
        end)
        H.Hekili.Engine.Output.status.combat = false
        -- rend: 8 s out on the clock (past 7.5 s), 7 s after the press (within it)
        tlPublish(H, 4)
        for _ = 1, 2 do -- Tick (the ETAs) runs before Draw
            H.ctl.now = H.ctl.now + 0.2
            d.__scripts.OnUpdate(d, 0.2)
        end
        local c = T.cells
        assert.are.equal("rend", c[1].Action)
        assert.are.equal("7.0", c[1].Eta:GetText()) -- press-relative, still 0.4 s on
        assert.is_true(c[1].Ring:IsShown())
        assert.are.equal("mortal_strike", c[2].Action)
        assert.are.equal("K1", c[2].Keybinding:GetText())
        assert.are.same({}, H.errors)
    end)

    it("defaults on, in the Timeline tab", function()
        local H = boot()
        assert.is_true(H.Hekili.DB.profile.displays.Primary.timeline.oocPinned)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "timeline", "tab_timeline", "sec_lane", "oocPinned" }, false)
        assert.is_false(H.Hekili.DB.profile.displays.Primary.timeline.oocPinned)
        H.Hekili:EmbedDisplayOptions()
        local tabs = H.Hekili.Options.args.displays.plugins.Primary.Primary.args.timeline.args
        assert.is_table(tabs.tab_timeline.args.sec_lane.args.oocPinned)
    end)
end)
