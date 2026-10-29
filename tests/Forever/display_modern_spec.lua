-- tests/Forever/display_modern_spec.lua (Modern display phase 1 plan; spec docs/superpowers/specs/2026-10-29-modern-
-- display-design.md): Modern is a core layer over the display's own style (§5.1, M2). The styles publish an optional
-- button contract; with the toggle on, the style draws the same picks (R1) and Truth paints the real cooldown swipe,
-- the usability edge and the proc mark (R2, R3, §3.2). The client's overlay answer and GetSpellCooldownDuration are
-- faked per instance (boot wraps fake.new only while it builds the instance, so other specs' wrappers stay theirs).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

local overlayed, durations = {}, {}
local fx = { n = 0, ignore = {} } -- GetSpellCooldownDuration: calls, and the last ignoreGCD per spell

local rec = {}
function rec.Show(self)
    rawset(self, "__shown", true)
end
function rec.Hide(self)
    rawset(self, "__shown", false)
end
function rec.SetShown(self, v)
    rawset(self, "__shown", v and true or false)
end
function rec.IsShown(self)
    return rawget(self, "__shown") == true
end
function rec.SetTexture(self, t)
    rawset(self, "__tex", t)
end
function rec.SetCooldown(self, start, duration)
    rawset(self, "__cdStart", start)
    rawset(self, "__cdDuration", duration)
end
function rec.SetCooldownFromDurationObject(self, dur)
    rawset(self, "__dur", dur)
end
local function instrument(f)
    if f then
        for k, fn in pairs(rec) do
            rawset(f, k, fn)
        end
    end
end

-- A headless Hekili with Primary on `style` and the Modern toggle `truth` (default off); every button, texture,
-- cooldown, veil and real-swipe frame records its calls.
local function boot(style, truth)
    for k in pairs(overlayed) do
        overlayed[k] = nil
    end
    for k in pairs(durations) do
        durations[k] = nil
    end
    fx.n = 0
    for k in pairs(fx.ignore) do
        fx.ignore[k] = nil
    end
    local saved = fake.new
    fake.new = function(...)
        local api, ctl = saved(...)
        api.C_SpellActivationOverlay.IsSpellOverlayed = function(id)
            return overlayed[id] == true
        end
        api.C_Spell.GetSpellCooldownDuration = function(id, ignoreGCD)
            fx.n = fx.n + 1
            fx.ignore[id] = ignoreGCD
            return durations[id]
        end
        return api, ctl
    end
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    fake.new = saved
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    local conf = H.Hekili.DB.profile.displays.Primary
    conf.style = style
    if conf.truth then -- Task 3 adds the field; Task 2's cases boot with it off
        conf.truth.enabled = truth == true
    end
    H.Hekili:BuildUI()
    local d = rawget(H.env, "HekiliDisplayPrimary")
    for _, b in ipairs(d.Buttons) do
        instrument(b)
        instrument(b.Texture)
        instrument(rawget(b, "Cooldown"))
    end
    local S = d.truthState
    if S and d.truthOn then
        for _, ov in ipairs(S.ov) do
            instrument(ov.cd)
            instrument(ov.veil)
        end
    end
    return H, d
end

local function ids(H)
    local out = {}
    for k, a in pairs(H.Hekili.Engine.Registry.Abilities()) do
        out[k] = a.id
    end
    return out
end

-- Every spell of the Warrior world usable (the fake answers unusable for a spell it was not told about).
local function usableAll(H)
    for _, id in pairs(ids(H)) do
        if type(id) == "number" and id > 0 then
            H.ctl.usable[id] = { true, false }
        end
    end
end

-- { name, seconds from now, focus tier or nil }
local SET = { { "mortal_strike", 1.0 }, { "overpower", 1.5 }, { "slam", 2.0 }, { "rend", 2.5 } }
local SET_FOCUS = { { "mortal_strike", 0.5 }, { "slam", 1.0 }, { "overpower", 2.0, 1 }, { "rend", 3.0 } }
local SET_ONE = { { "slam", 0.3 } }

local function publish(H, set)
    local abilities = H.Hekili.Engine.Registry.Abilities()
    local now = H.ctl.now
    local s = H.ns.Output.Begin("Primary")
    for i, e in ipairs(set) do
        local r = s[i]
        r.actionName, r.actionID = e[1], abilities[e[1]].id
        r.texture, r.keybind = "tex" .. i, "K" .. i
        r.time, r.exact_time, r.focus = e[2], now + e[2], e[3]
    end
    H.ns.Output.Publish("Primary", #set)
end

local function blank(H)
    H.ns.Output.Begin("Primary")
    H.ns.Output.Publish("Primary", 0)
end

local function frame(H, d, dt)
    H.ctl.now = H.ctl.now + dt
    d.__scripts.OnUpdate(d, dt)
end

-- What each button shows, with its contract fields (the R1 parity key).
local function picks(d)
    local t = {}
    for c, b in ipairs(d.Buttons) do
        t[c] = { b:IsShown(), b.Action or false, rawget(b.Texture, "__tex") or false, b.recIndex, b.isFocus or false }
    end
    return t
end

-- The button drawing record 1 (the press icon), or 0.
local function nextButton(d)
    for c, b in ipairs(d.Buttons) do
        if b.recIndex == 1 then
            return c
        end
    end
    return 0
end

describe("the button contract (spec §5.1)", function()
    it("Classic: each button's record while it draws one, 0 past the records, on a blank publish and after Clear", function()
        local H, d = boot("classic")
        usableAll(H)
        publish(H, SET)
        frame(H, d, 0.2)
        local n = H.Hekili.DB.profile.displays.Primary.numIcons
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(c <= n and c <= #SET and c or 0, b.recIndex, "button " .. c)
            assert.is_falsy(b.isFocus)
            assert.is_falsy(b.round)
        end
        assert.are.equal(1, nextButton(d))
        publish(H, SET_ONE)
        frame(H, d, 0.2)
        assert.are.same({ 1, 0 }, { d.Buttons[1].recIndex, d.Buttons[2].recIndex })
        blank(H)
        frame(H, d, 0.2)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "button " .. c)
        end
        publish(H, SET)
        frame(H, d, 0.2)
        d.style.Clear(d)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "button " .. c)
        end
        assert.are.same({}, H.errors)
    end)

    it("Timeline: each cell's record and the focus cell; cell 1 is round", function()
        local H, d = boot("timeline")
        usableAll(H)
        publish(H, SET_FOCUS)
        frame(H, d, 0.2)
        local T = d.styleFrames.timeline
        assert.is_true(T.focused)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(T.rec[c], b.recIndex, "cell " .. c)
            assert.are.equal(c == 1, b.isFocus == true, "cell " .. c)
        end
        assert.are.equal(3, d.Buttons[1].recIndex) -- the flagged record in the now circle
        assert.are.equal(T.press, nextButton(d))
        assert.is_true(d.Buttons[1].round)
        assert.is_falsy(d.Buttons[2].round)
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_false(d.Buttons[1].isFocus)
        blank(H)
        frame(H, d, 0.2)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "cell " .. c)
            assert.is_false(b.isFocus, "cell " .. c)
        end
        publish(H, SET)
        frame(H, d, 0.2)
        d.style.Clear(d)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "cell " .. c)
        end
        assert.are.same({}, H.errors)
    end)

    it("costs nothing per frame", function()
        for _, style in ipairs({ "classic", "timeline" }) do
            local H, d = boot(style)
            usableAll(H)
            publish(H, SET)
            for _ = 1, 3 do
                frame(H, d, 0.2)
            end
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for _ = 1, 1000 do
                d.__scripts.OnUpdate(d, 0.01)
            end
            local bytes = (collectgarbage("count") - before) * 1024
            collectgarbage("restart")
            assert.are.equal(0, bytes, style)
        end
    end)

    it("Timeline: timersHidden follows Timers Out of Combat and combat", function()
        local H, d = boot("timeline")
        usableAll(H)
        local tl = H.Hekili.DB.profile.displays.Primary.timeline
        local function all(v, msg)
            for c, b in ipairs(d.Buttons) do
                assert.are.equal(v, b.timersHidden == true, msg .. " cell " .. c)
            end
        end
        tl.oocTimers = false
        publish(H, SET)
        frame(H, d, 0.2)
        all(true, "ooc, option off")
        tl.oocTimers = true
        publish(H, SET)
        frame(H, d, 0.2)
        all(false, "ooc, option on")
        tl.oocTimers = false
        publish(H, SET)
        frame(H, d, 0.2)
        all(true, "ooc, option off again")
        H.Hekili.Engine.Output.status.combat = true
        publish(H, SET)
        frame(H, d, 0.2)
        all(false, "in combat")
        H.Hekili.Engine.Output.status.combat = false
        tl.oocTimers = true
        publish(H, SET)
        frame(H, d, 0.2)
        all(false, "back out of combat, option on")
        H.Hekili.Engine.Output.status.combat = false
        assert.are.same({}, H.errors)
    end)
end)
