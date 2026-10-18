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

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
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
    local conf = H.Hekili.DB.profile.displays.Primary
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
        local conf = H.Hekili.DB.profile.displays.Primary
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
