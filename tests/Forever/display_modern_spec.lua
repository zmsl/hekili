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
function rec.SetDesaturated(self, v)
    rawset(self, "__desat", v and true or false)
end
function rec.SetVertexColor(self, r, g, b, a) -- four fields, no table: a style may tint every frame
    rawset(self, "__vr", r)
    rawset(self, "__vg", g)
    rawset(self, "__vb", b)
    rawset(self, "__va", a)
end
function rec.SetAlpha(self, a)
    rawset(self, "__alpha", a)
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

local ACTIVE = { isActive = true, isOnGCD = false, startTime = fake.SECRET, duration = fake.SECRET }
local ON_GCD = { isActive = true, isOnGCD = true, startTime = fake.SECRET, duration = fake.SECRET }

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

-- What each button shows, with its contract fields and the style's own surfaces: its cooldown as set, desaturation,
-- vertex colour, alpha and glow (the R1 parity key). b.Cooldown's shown state is left out: Truth swaps it for its real
-- swipe (R2), asserted on its own.
local function picks(d)
    local t = {}
    for c, b in ipairs(d.Buttons) do
        local cd, tex = rawget(b, "Cooldown"), b.Texture
        t[c] = {
            b:IsShown(),
            b.Action or false,
            rawget(tex, "__tex") or false,
            b.recIndex,
            b.isFocus or false,
            cd and rawget(cd, "__cdStart") or false,
            cd and rawget(cd, "__cdDuration") or false,
            rawget(tex, "__desat") or false,
            rawget(tex, "__vr") or false,
            rawget(tex, "__vg") or false,
            rawget(tex, "__vb") or false,
            rawget(tex, "__va") or false,
            rawget(b, "__alpha") or false,
            b.glowing or false,
        }
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
    it(
        "Classic: each button's record while it draws one, 0 past the records, on a blank publish and after Clear",
        function()
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
        end
    )

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

describe("the Modern toggle (spec §5.1, §7)", function()
    for _, style in ipairs({ "classic", "timeline" }) do
        it("leaves " .. style .. "'s picks and contract unchanged with the toggle on (R1 parity)", function()
            for _, set in ipairs({ SET, SET_FOCUS, SET_ONE }) do
                local H, d = boot(style)
                usableAll(H)
                publish(H, set)
                frame(H, d, 0.2)
                local want = picks(d)
                local H2, d2 = boot(style, true)
                usableAll(H2)
                publish(H2, set)
                frame(H2, d2, 0.2)
                assert.are.same(want, picks(d2))
                assert.are.equal(H2.ns.UI.Styles[style], d2.style)
                assert.is_true(d2.truthOn)
                assert.are.same({}, H2.errors)
            end
        end)

        it("allocates nothing over 1,000 display frames with the toggle on, on " .. style, function()
            local H, d = boot(style, true)
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
            assert.are.same({}, H.errors)
            assert.are.equal(0, bytes)
        end)
    end

    it("defaults off, in its own core field and one Modern tab on every style", function()
        local H = boot("classic")
        local conf = H.Hekili.DB.profile.displays.Primary
        -- AceDB serves defaults through metatables: read each field
        local t = conf.truth
        assert.are.same({ false, true, true, true }, { t.enabled, t.swipes, t.edge, t.confirm })
        assert.is_true(H.ns.UI.StyleNameTaken("truth"))
        assert.is_nil(H.ns.UI.Styles.modern)
        H.Hekili:EmbedDisplayOptions()
        local args = H.Hekili.Options.args.displays.plugins.Primary.Primary.args
        assert.is_table(args.truth)
        assert.is_nil(args.truth.hidden)
        assert.is_nil(args.classic.args.tab_modern)
        local path = { "displays", "Primary", "truth", "enabled" }
        assert.is_false(H.Hekili:GetDisplayOption(path))
        assert.is_true(args.truth.args.swipes.disabled())
        H.Hekili:SetDisplayOption(path, true)
        assert.is_true(conf.truth.enabled)
        assert.is_false(args.truth.args.swipes.disabled())
        for _, k in ipairs({ "swipes", "edge", "confirm" }) do
            assert.is_true(H.Hekili:GetDisplayOption({ "displays", "Primary", "truth", k }), k)
        end
        assert.is_nil(args.truth.args.execute)
        assert.is_nil(args.truth.args.ride)
        conf.style = "timeline"
        assert.is_nil(args.truth.hidden) -- core's tab, whatever the style
        assert.are.same({}, H.errors)
    end)

    it("disables the Modern tab's sub-toggles exactly while its toggle is off (on Multi: Primary's)", function()
        local H = boot("classic")
        H.Hekili:EmbedDisplayOptions()
        local plugins = H.Hekili.Options.args.displays.plugins
        local truth = H.Hekili.DB.profile.displays.Primary.truth
        for _, on in ipairs({ false, true, false }) do
            truth.enabled = on
            for _, args in ipairs({ plugins.Primary.Primary.args, plugins.Multi.Multi.args }) do
                assert.is_nil(args.truth.args.enabled.disabled)
                for _, k in ipairs({ "swipes", "edge", "confirm" }) do
                    assert.are.equal(not on, args.truth.args[k].disabled(), k)
                end
            end
        end
        assert.are.same({}, H.errors)
    end)

    it("registers its events only while on, again after a Clear on the next draw, across a style switch", function()
        local H, d = boot("classic", true)
        local function registered()
            local n = 0
            for _, e in ipairs(H.ns.UI.Truth.EVENTS) do
                n = n + (d:IsEventRegistered(e) and 1 or 0)
            end
            return n
        end
        assert.are.equal(3, registered())
        d.style.Clear(d) -- what core's unsubscribe does, then Truth's
        H.ns.UI.Truth.Clear(d)
        assert.are.equal(0, registered())
        publish(H, SET)
        frame(H, d, 0.2)
        assert.are.equal(3, registered())
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "timeline")
        H.Hekili:BuildUI()
        assert.are.equal(3, registered())
        assert.are.equal(d.styleFrames.timeline.cells, d.truthState.buttons)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "truth", "enabled" }, false)
        H.Hekili:BuildUI()
        assert.are.equal(0, registered())
        assert.is_false(d.truthOn)
        assert.are.same({}, H.errors)
    end)

    it("runs nothing with the toggle off", function()
        local H, d = boot("classic")
        local T, calls = H.ns.UI.Truth, 0
        for _, k in ipairs({ "Build", "Tick", "Draw", "OnGameEvent", "Clear" }) do
            local f = T[k]
            T[k] = function(...)
                calls = calls + 1
                return f(...)
            end
        end
        H.Hekili:BuildUI()
        usableAll(H)
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1)
        d.style.Clear(d)
        assert.are.equal(0, calls)
        assert.is_false(d.truthOn)
        assert.are.same({}, H.errors)
    end)

    it("paints nothing on a style without the button contract", function()
        local H = boot("classic")
        assert.is_true(H.Hekili:RegisterDisplayStyle("bare", {
            api = H.Hekili.DisplayStyleAPI,
            label = "Bare",
            Build = function(d)
                local b = rawget(d, "bareButton") or H.env.CreateFrame("Button", nil, d)
                rawset(d, "bareButton", b)
                return { b }
            end,
            Draw = function() end,
            Tick = function() end,
            OnGameEvent = function() end,
            Clear = function() end,
            Perimeter = function() end,
            UpdateKeybindings = function() end,
            Options = function()
                return nil
            end,
        }))
        local conf = H.Hekili.DB.profile.displays.Primary
        conf.style, conf.truth.enabled = "bare", true
        H.Hekili:BuildUI()
        local d = rawget(H.env, "HekiliDisplayPrimary")
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike] = { isActive = true, isOnGCD = false }
        durations[A.mortal_strike] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(d.truthOn)
        assert.are.equal(0, d.truthState.ov[1].spell)
        assert.is_nil(d.truthState.ov[1].cd)
        assert.are.equal(0, fx.n)
        assert.are.same({}, H.errors)
    end)

    it("keeps every probe-gated overlay off in code (M1)", function()
        local H = boot("classic", true)
        assert.are.same({ strip = false, execute = false, ride = false, cdm = false }, H.ns.UI.Truth.VERIFIED)
    end)
end)

describe("Modern's real cooldown swipe (R2, §3.4)", function()
    it("shows the game's cooldown while it runs and hands the style its own swipe back when it ends", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike] = ACTIVE
        H.ctl.cooldown[A.overpower] = ON_GCD
        durations[A.mortal_strike], durations[A.overpower] = fake.SECRET, fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local ov, b = d.truthState.ov, d.Buttons
        assert.is_true(ov[1].real)
        assert.is_true(rawequal(fake.SECRET, ov[1].cd.__dur))
        assert.is_true(ov[1].cd.__shown)
        assert.is_false(b[1].Cooldown.__shown)
        assert.is_false(fx.ignore[A.mortal_strike]) -- the press icon's swipe includes the GCD
        assert.is_false(ov[2].real) -- the GCD alone: the style's swipe
        assert.is_nil(fx.ignore[A.overpower])
        H.ctl.cooldown[A.mortal_strike] = nil
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_false(ov[1].real)
        assert.is_false(ov[1].cd.__shown)
        assert.is_true(b[1].Cooldown.__shown)
        -- R2: the style's own delay look (classic's extend) still runs to Hekili's time
        local exact = H.Hekili.Engine.Output.Primary.recs[1].exact_time
        assert.is_true(math.abs(b[1].Cooldown.__cdStart + b[1].Cooldown.__cdDuration - exact) < 1e-6)
        assert.are.same({}, H.errors)
    end)

    it("fetches a queued icon's cooldown without the GCD; ends on the widget's own OnCooldownDone", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.overpower] = ACTIVE
        durations[A.overpower] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local ov = d.truthState.ov[2]
        assert.is_true(fx.ignore[A.overpower])
        assert.is_true(ov.real)
        ov.cd.__scripts.OnCooldownDone(ov.cd)
        assert.is_false(ov.real)
        assert.is_true(d.Buttons[2].Cooldown.__shown)
        assert.are.same({}, H.errors)
    end)

    it("fetches only on a spell change and the cooldown events, never per frame", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike], H.ctl.cooldown[A.overpower] = ACTIVE, ACTIVE
        durations[A.mortal_strike], durations[A.overpower] = fake.SECRET, fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        assert.are.equal(2, fx.n)
        for _ = 1, 50 do
            frame(H, d, 0.01)
        end
        assert.are.equal(2, fx.n)
        publish(H, SET) -- the same spells in the same slots
        frame(H, d, 0.01)
        assert.are.equal(2, fx.n)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.are.equal(4, fx.n)
        H.Fire("SPELL_UPDATE_CHARGES")
        assert.are.equal(6, fx.n)
        publish(H, { { "overpower", 1.0 }, { "mortal_strike", 1.5 } }) -- both slots change spell
        frame(H, d, 0.01)
        assert.are.equal(8, fx.n)
        assert.is_false(fx.ignore[A.overpower]) -- now the press icon
        assert.is_true(fx.ignore[A.mortal_strike])
        assert.are.same({}, H.errors)
    end)

    it("never fetches for an item or a charge spell, and not with swipes off", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike], H.ctl.cooldown[A.overpower] = ACTIVE, ACTIVE
        durations[A.mortal_strike], durations[A.overpower] = fake.SECRET, fake.SECRET
        rawset(H.Hekili.Engine.Registry.Abilities().overpower, "charges", 2)
        local s = H.ns.Output.Begin("Primary")
        s[1].actionName, s[1].actionID, s[1].item = "mortal_strike", A.mortal_strike, 1234 -- an item record
        s[1].texture, s[1].time, s[1].exact_time = "t1", 1, H.ctl.now + 1
        s[2].actionName, s[2].actionID = "overpower", A.overpower
        s[2].texture, s[2].time, s[2].exact_time = "t2", 1.5, H.ctl.now + 1.5
        H.ns.Output.Publish("Primary", 2)
        frame(H, d, 0.2)
        assert.are.equal(0, fx.n)
        H.Hekili.DB.profile.displays.Primary.truth.swipes = false
        H.Hekili:BuildUI()
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.are.equal(0, fx.n)
        assert.are.same({}, H.errors)
    end)

    it("shows the real swipe again on the first publish after a Clear", function()
        local H, d = boot("timeline", true)
        local A = ids(H)
        usableAll(H)
        H.Hekili.DB.profile.displays.Primary.timeline.oocTimers = true -- RM1: Timeline's timers show out of combat
        H.ctl.cooldown[A.mortal_strike] = ACTIVE
        durations[A.mortal_strike] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local T = d.styleFrames.timeline
        local c = T.press
        local ov = d.truthState.ov[c]
        assert.is_true(ov.real)
        d.style.Clear(d) -- what core's unsubscribe does, then Truth's
        H.ns.UI.Truth.Clear(d)
        assert.is_false(ov.cd.__shown)
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_true(ov.real)
        assert.is_true(ov.cd.__shown)
        assert.is_false(T.cells[c].Cooldown.__shown)
        assert.is_nil(d.truthState.ov[3].cd) -- a lane cell has no swipe
        assert.are.same({}, H.errors)
    end)

    it("passes the duration object only to the swipe: one read site, no error on the secret sentinel", function()
        local reads = {}
        for l in io.lines("src/Hekili/UI/Truth.lua") do
            local code = l:gsub("%-%-.*$", "")
            if code:find("Display%.") or code:find("Facade%.Display") then
                reads[#reads + 1] = code:match("^%s*(.-)%s*$")
            end
        end
        assert.are.equal(2, #reads)
        assert.is_truthy(reads[1]:match("^local Display = ns%.Facade%.Display$"), reads[1])
        assert.is_truthy(reads[2]:match("^ov%.dur = Display%.C_Spell%.GetSpellCooldownDuration%(.*%)$"), reads[2])
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        for _, id in pairs(A) do
            H.ctl.cooldown[id], durations[id] = ACTIVE, fake.SECRET -- raises on compare, arithmetic, concat, index
        end
        publish(H, SET)
        for _ = 1, 5 do
            frame(H, d, 0.2)
            H.Fire("SPELL_UPDATE_COOLDOWN")
            H.Fire("SPELL_UPDATE_USABLE")
        end
        assert.are.same({}, H.errors)
    end)
    it(
        "hides the real swipe while the style hides its own timers, and brings it back when they return (RM1)",
        function()
            local H, d = boot("timeline", true)
            local A = ids(H)
            usableAll(H)
            local tl = H.Hekili.DB.profile.displays.Primary.timeline
            tl.oocTimers = false -- out of combat: Timeline hides its sweeps
            H.ctl.cooldown[A.mortal_strike] = ACTIVE
            durations[A.mortal_strike] = fake.SECRET
            publish(H, SET)
            frame(H, d, 0.2)
            local T = d.styleFrames.timeline
            local c = T.press
            local ov, b = d.truthState.ov[c], T.cells[c]
            assert.is_true(b.timersHidden)
            assert.is_true(ov.real)
            assert.is_falsy(ov.cd.__shown)
            tl.oocTimers = true
            publish(H, SET)
            frame(H, d, 0.2)
            assert.is_false(b.timersHidden)
            assert.is_true(ov.cd.__shown)
            assert.is_false(b.Cooldown.__shown)
            tl.oocTimers = false
            publish(H, SET)
            frame(H, d, 0.2)
            assert.is_true(b.timersHidden)
            assert.is_false(ov.cd.__shown)
            assert.is_true(b.Cooldown.__shown)
            H.Fire("SPELL_UPDATE_COOLDOWN") -- a refetch while hidden keeps it hidden
            assert.is_true(ov.real)
            assert.is_false(ov.cd.__shown)
            assert.are.same({}, H.errors)
        end
    )

    for _, style in ipairs({ "classic", "timeline" }) do
        it(
            "keeps " .. style .. "'s own surfaces with a real swipe running; only its Cooldown swaps (R1, R2)",
            function()
                local function run(on)
                    local H, d = boot(style, on)
                    local A = ids(H)
                    usableAll(H)
                    H.Hekili.DB.profile.displays.Primary.timeline.oocTimers = true
                    H.ctl.cooldown[A.mortal_strike] = ACTIVE
                    durations[A.mortal_strike] = fake.SECRET
                    publish(H, SET)
                    frame(H, d, 0.2)
                    frame(H, d, 0.2)
                    assert.are.same({}, H.errors)
                    return d
                end
                local off, on = run(false), run(true)
                assert.are.same(picks(off), picks(on))
                local swaps = 0
                for c, b in ipairs(on.Buttons) do
                    local cd, ov = rawget(b, "Cooldown"), on.truthState.ov[c]
                    if ov.cdShown then
                        swaps = swaps + 1
                        assert.are.equal(1, b.recIndex, "button " .. c)
                        assert.is_true(ov.cd.__shown, "button " .. c)
                        assert.is_false(cd.__shown, "button " .. c)
                    elseif cd then
                        assert.are.equal(rawget(off.Buttons[c].Cooldown, "__shown"), cd.__shown, "button " .. c)
                    end
                end
                assert.are.equal(1, swaps)
            end
        )
    end

    it("clears on core's own paths: an unsubscribe (alpha 0) and Deactivate", function()
        for _, path in ipairs({ "unsubscribe", "deactivate" }) do
            local H, d = boot("classic", true)
            local A = ids(H)
            usableAll(H)
            H.ctl.cooldown[A.mortal_strike] = ACTIVE
            durations[A.mortal_strike] = fake.SECRET
            publish(H, SET)
            frame(H, d, 0.2)
            local ov = d.truthState.ov[1]
            assert.is_true(ov.cd.__shown, path)
            if path == "unsubscribe" then
                d.Active = false
                d:UpdateAlpha()
            else
                d:Deactivate()
            end
            assert.is_false(ov.cd.__shown, path)
            assert.is_false(ov.real, path)
            assert.is_true(d.Buttons[1].Cooldown.__shown, path)
            for _, e in ipairs(H.ns.UI.Truth.EVENTS) do
                assert.is_false(d:IsEventRegistered(e), path .. " " .. e)
            end
            assert.are.same({}, H.errors)
        end
    end)
end)
