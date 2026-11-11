-- tests/Forever/bar_glow_spec.lua: the action bar glow (UI/BarGlow.lua). A display's first recommendation glows the real
-- action buttons that cast it in one colour, its second in another, through LibCustomGlow's proc glow under Hekili's own
-- keys. The buttons come from walking the bar frames (Blizzard's keyboard bars, Forever's gamepad bars, ElvUI) and
-- reading each one's current action slot; the ability behind a slot is the keybind reader's own lookup.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

-- The fake client's bars: slot -> { type, id }; macros: id -> spell id or item name.
local world

local fakeNew = fake.new
local function install()
    fake.new = function(...)
        local api, ctl = fakeNew(...)
        api.GetActionInfo = function(slot)
            local a = world.actions[slot]
            if a then
                return a[1], a[2]
            end
        end
        api.GetMacroSpell = function(id)
            return world.macroSpell[id]
        end
        api.GetMacroItem = function(id)
            return world.macroItem[id]
        end
        return api, ctl
    end
end

local function boot()
    install()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    fake.new = fakeNew
    assert.are.same({}, H.loadErrors)
    assert(headless.cycle(H, H.ctl.now + 0.2))
    return H
end

-- A recording LibCustomGlow: lit[button][key] = the colour table the start was given.
local function recorder()
    local g = { lit = {}, starts = 0, stops = 0 }
    function g.ProcGlow_Start(b, opts)
        g.starts = g.starts + 1
        g.lit[b] = g.lit[b] or {}
        g.lit[b][opts.key] = { opts.color[1], opts.color[2], opts.color[3], opts.color[4] }
    end
    function g.ProcGlow_Stop(b, key)
        g.stops = g.stops + 1
        if g.lit[b] then
            g.lit[b][key] = nil
        end
    end
    -- the colour of the one glow on `b`, or nil
    function g.on(b)
        local n, color, key = 0, nil, nil
        for k, c in pairs(g.lit[b] or {}) do
            n, color, key = n + 1, c, k
        end
        assert(n <= 1, "two glows on one button")
        return color, key
    end
    return g
end

local function button(slot)
    return { action = slot }
end

local function id(H, name)
    return H.Hekili.Engine.Registry.Abilities()[name].id
end

local function out(first, second, count)
    return {
        count = count or (second and 2 or 1),
        version = 5,
        recs = { { actionName = first }, { actionName = second } },
    }
end

local NOW = { 1, 0.82, 0, 1 }
local NEXT = { 0.3, 0.6, 1, 1 }

describe("action bar glow", function()
    local H, BG, glow, d, cfg

    before_each(function()
        world = { actions = {}, macroSpell = {}, macroItem = {} }
        H = boot()
        BG = H.ns.UI.BarGlow
        glow = recorder()
        BG.Glower = glow
        d = { id = "Primary", styleState = {}, blankVersion = -1 }
        cfg = {
            enabled = true,
            colorNow = { 1, 0.82, 0, 1 },
            glowNext = true,
            colorNext = { 0.3, 0.6, 1, 1 },
        }
    end)

    local function bars()
        world.actions[1] = { "spell", id(H, "mortal_strike") }
        world.actions[2] = { "spell", id(H, "overpower") }
        world.actions[3] = { "spell", id(H, "slam") }
        world.actions[25] = { "spell", id(H, "mortal_strike") } -- the same ability on a second bar
        local e = H.env
        e.ActionButton1, e.ActionButton2, e.ActionButton3 = button(1), button(2), button(3)
        e.MultiBarBottomLeftButton1 = button(25)
        BG.Rescan()
        return e
    end

    it("glows the buttons casting record 1 in the now colour and record 2's in the next colour", function()
        local e = bars()
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NOW, (glow.on(e.MultiBarBottomLeftButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
        assert.is_nil(glow.on(e.ActionButton3))
    end)

    it("glows only the now colour when both records are one ability", function()
        local e = bars()
        BG.Update(d, cfg, out("mortal_strike", "mortal_strike"), 3)
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it("glows no next button when the next option is off, or the display shows one icon", function()
        local e = bars()
        cfg.glowNext = false
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.is_nil(glow.on(e.ActionButton2))
        cfg.glowNext = true
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 1)
        assert.is_nil(glow.on(e.ActionButton2))
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
    end)

    it("moves the glows when the recommendation changes, and stops the old ones", function()
        local e = bars()
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        BG.Update(d, cfg, out("overpower", "slam"), 3)
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.MultiBarBottomLeftButton1))
        assert.are.same(NOW, (glow.on(e.ActionButton2)))
        assert.are.same(NEXT, (glow.on(e.ActionButton3)))
    end)

    it("keeps the now glow running while only the next record changes", function()
        local e = bars()
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        local starts = glow.starts
        BG.Update(d, cfg, out("mortal_strike", "slam"), 3)
        assert.are.equal(starts + 1, glow.starts) -- the next glow only
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton3)))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it("stops every glow when the feature is off, the display is blank, or it is cleared", function()
        local e = bars()
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        cfg.enabled = false
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.ActionButton2))
        cfg.enabled = true
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        local blank = out("mortal_strike", "overpower")
        d.blankVersion = blank.version
        BG.Update(d, cfg, blank, 3)
        assert.is_nil(glow.on(e.ActionButton1))
        d.blankVersion = -1
        BG.Update(d, cfg, out("mortal_strike", "overpower", 0), 3)
        assert.is_nil(glow.on(e.ActionButton1))
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        BG.Clear(d)
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it("repaints a colour changed in the options", function()
        local e = bars()
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        cfg.colorNow = { 0, 1, 0, 1 }
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.are.same({ 0, 1, 0, 1 }, (glow.on(e.ActionButton1)))
    end)

    it("glows an item button and a macro button by the ability each casts", function()
        local e = H.env
        world.actions[1] = { "item", 5512 } -- a healthstone
        world.actions[2] = { "macro", 7 }
        world.actions[3] = { "macro", 8 }
        world.macroSpell[7] = id(H, "overpower")
        world.macroItem[8] = "Healthstone"
        e.ActionButton1, e.ActionButton2, e.ActionButton3 = button(1), button(2), button(3)
        BG.Rescan()
        BG.Update(d, cfg, out("healthstone", "overpower"), 3)
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
        assert.is_nil(glow.on(e.ActionButton3)) -- a macro that casts an item the lookup does not know
    end)

    it("glows a gamepad bar button through its current action", function()
        local e = H.env
        world.actions[190] = { "spell", id(H, "mortal_strike") }
        local btn = button(190)
        local bar = {
            GetChildren = function()
                return btn
            end,
        }
        e.GamepadMainActionBarFrame = {
            PageUnit = {
                GetChildren = function()
                    return bar
                end,
            },
        }
        BG.Rescan()
        BG.Update(d, cfg, out("mortal_strike"), 3)
        assert.are.same(NOW, (glow.on(btn)))
        -- the page turns: the same button now holds another action
        btn.action = 191
        world.actions[191] = { "spell", id(H, "slam") }
        BG.Rescan()
        BG.Update(d, cfg, out("mortal_strike"), 3)
        assert.is_nil(glow.on(btn))
        BG.Update(d, cfg, out("slam"), 3)
        assert.are.same(NOW, (glow.on(btn)))
    end)

    it("follows a button whose action changes away", function()
        local e = bars()
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        e.ActionButton1.action = 3 -- now holds slam
        BG.Rescan()
        BG.Update(d, cfg, out("mortal_strike", "overpower"), 3)
        assert.is_nil(glow.on(e.ActionButton1))
        assert.are.same(NOW, (glow.on(e.MultiBarBottomLeftButton1)))
    end)

    it("reads an ElvUI button's state action", function()
        local e = H.env
        world.actions[4] = { "spell", id(H, "slam") }
        e.ElvUI_Bar1Button1 = { _state_action = 4, action = 99 }
        BG.Rescan()
        BG.Update(d, cfg, out("slam"), 3)
        assert.are.same(NOW, (glow.on(e.ElvUI_Bar1Button1)))
    end)

    it("allocates nothing in an update when the recommendation is unchanged", function()
        bars()
        local o = out("mortal_strike", "overpower")
        BG.Update(d, cfg, o, 3)
        BG.Update(d, cfg, o, 3)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            BG.Update(d, cfg, o, 3)
        end
        local bytes = (collectgarbage("count") - before) * 1024
        collectgarbage("restart")
        assert.are.equal(0, bytes)
    end)

    it("is on by default for the Primary display only, in the classic and timeline styles", function()
        local displays = H.Hekili.DB.profile.displays
        for _, style in ipairs({ "classic", "timeline" }) do
            local p, a = displays.Primary[style].barGlow, displays.AOE[style].barGlow
            assert.is_true(p.enabled)
            assert.is_false(a.enabled)
            assert.are.same({ 1, 0.82, 0, 1 }, p.colorNow)
            assert.is_true(p.glowNext)
            assert.are.same({ 0.3, 0.6, 1, 1 }, p.colorNext)
        end
    end)

    it("hides the SpellFlash tab without SpellFlashCore", function()
        assert.is_nil(H.env.SpellFlashCore)
        local conf = H.Hekili.DB.profile.displays.Primary
        local zones = { "primary", "queued", legacy = true }
        local flash = H.ns.StyleOptions.flash("classic", zones, 8, "Primary", conf)
        assert.is_true(flash.hidden())
        local tab = H.ns.StyleOptions.barGlow("classic", zones, 8.5, "Primary", conf)
        assert.is_falsy(tab.hidden and tab.hidden())
    end)
end)
