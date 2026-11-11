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

local NOW = { 1, 0.82, 0, 1 }
local NEXT = { 0.3, 0.6, 1, 1 }

describe("action bar glow", function()
    local H, BG, glow, cfg

    -- Publishes records into the Primary stream the way the engine does; BarGlow is a subscriber of it.
    local function put(first, second, count)
        local abilities = H.Hekili.Engine.Registry.Abilities()
        local o = H.ns.Output.Begin("Primary")
        local list = { first, second }
        for i = 1, 2 do
            local a = list[i]
            if a then
                o[i].actionName, o[i].actionID, o[i].texture = a, abilities[a] and abilities[a].id or 0, "tex" .. i
                o[i].time, o[i].exact_time = i, H.ctl.now + i
            end
        end
        H.ns.Output.steady = false -- the raw picks: the hold is its own spec
        H.ns.Output.Publish("Primary", count or (second and 2 or first and 1 or 0))
    end

    -- Is the glow an active (non-passive) subscriber of `name`'s stream?
    local function active(name)
        local o = H.Hekili.Engine.Output[name]
        for i = 1, o.subs.n do
            if o.subs[i] == BG.OnPublish then
                return o.passive[i] == false
            end
        end
        return false
    end

    before_each(function()
        world = { actions = {}, macroSpell = {}, macroItem = {} }
        H = boot()
        BG = H.ns.UI.BarGlow
        glow = recorder()
        BG.Glower = glow
        cfg = H.Hekili.DB.profile.barGlow
        cfg.enabled, cfg.combatOnly = true, false
        BG.Apply()
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
        put("mortal_strike", "overpower")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NOW, (glow.on(e.MultiBarBottomLeftButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
        assert.is_nil(glow.on(e.ActionButton3))
    end)

    it("glows only the now colour when both records are one ability", function()
        local e = bars()
        put("mortal_strike", "mortal_strike")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it("glows no next button when the next option is off", function()
        local e = bars()
        cfg.glowNext = false
        BG.Apply()
        put("mortal_strike", "overpower")
        assert.is_nil(glow.on(e.ActionButton2))
        cfg.glowNext = true
        BG.Apply()
        put("mortal_strike", "overpower")
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
    end)

    it("moves the glows when the recommendation changes, and stops the old ones", function()
        local e = bars()
        put("mortal_strike", "overpower")
        put("overpower", "slam")
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.MultiBarBottomLeftButton1))
        assert.are.same(NOW, (glow.on(e.ActionButton2)))
        assert.are.same(NEXT, (glow.on(e.ActionButton3)))
    end)

    it("keeps the now glow running while only the next record changes", function()
        local e = bars()
        put("mortal_strike", "overpower")
        local starts = glow.starts
        put("mortal_strike", "slam")
        assert.are.equal(starts + 1, glow.starts) -- the next glow only
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton3)))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it("stops every glow when the feature is off, the display is blank, or it is cleared", function()
        local e = bars()
        put("mortal_strike", "overpower")
        cfg.enabled = false
        BG.Apply()
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.ActionButton2))
        cfg.enabled = true
        BG.Apply()
        put("mortal_strike", "overpower")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        put("mortal_strike", "overpower", 0) -- the stream publishes none
        assert.is_nil(glow.on(e.ActionButton1))
        put("mortal_strike", "overpower")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        cfg.enabled = false
        BG.Apply()
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it("repaints a colour changed in the options", function()
        local e = bars()
        put("mortal_strike", "overpower")
        cfg.colorNow = { 0, 1, 0, 1 }
        BG.Apply()
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
        put("healthstone", "overpower")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
        assert.is_nil(glow.on(e.ActionButton3)) -- a macro that casts an item the lookup does not know
    end)

    it("glows a macro slot that answers its spell's id directly (Forever, in game: 'macro 778')", function()
        local e = H.env
        world.actions[37] = { "macro", id(H, "overpower") } -- no macro index: GetMacroSpell would answer nothing
        e.MultiBarLeftButton1 = button(37)
        BG.Rescan()
        put("overpower")
        assert.are.same(NOW, (glow.on(e.MultiBarLeftButton1)))
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
        put("mortal_strike")
        assert.are.same(NOW, (glow.on(btn)))
        -- the page turns: the same button now holds another action
        btn.action = 191
        world.actions[191] = { "spell", id(H, "slam") }
        BG.Rescan()
        put("mortal_strike")
        assert.is_nil(glow.on(btn))
        put("slam")
        assert.are.same(NOW, (glow.on(btn)))
    end)

    it("follows a button whose action changes away", function()
        local e = bars()
        put("mortal_strike", "overpower")
        e.ActionButton1.action = 3 -- now holds slam
        BG.Rescan()
        put("mortal_strike", "overpower")
        assert.is_nil(glow.on(e.ActionButton1))
        assert.are.same(NOW, (glow.on(e.MultiBarBottomLeftButton1)))
    end)

    it("reads an ElvUI button's state action", function()
        local e = H.env
        world.actions[4] = { "spell", id(H, "slam") }
        e.ElvUI_Bar1Button1 = { _state_action = 4, action = 99 }
        BG.Rescan()
        put("slam")
        assert.are.same(NOW, (glow.on(e.ElvUI_Bar1Button1)))
    end)

    it("allocates nothing in an update when the recommendation is unchanged", function()
        bars()
        put("mortal_strike", "overpower")
        local o = H.Hekili.Engine.Output.Primary
        BG.OnPublish("Primary", o.version, o)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            BG.OnPublish("Primary", o.version, o)
        end
        local bytes = (collectgarbage("count") - before) * 1024
        collectgarbage("restart")
        assert.are.equal(0, bytes)
    end)

    it("is one global setting: off by default, follows Primary, in combat only, the owner's colours", function()
        local fresh = H.Hekili.GetDefaults(H.Hekili).profile.barGlow
        assert.is_false(fresh.enabled)
        assert.are.equal("Primary", fresh.follow)
        assert.are.same({ 1, 0.82, 0, 1 }, fresh.colorNow)
        assert.is_true(fresh.glowNext)
        assert.are.same({ 0.3, 0.6, 1, 1 }, fresh.colorNext)
        assert.is_true(fresh.combatOnly)
    end)

    it("has its own options page under Displays (owner 2026-11-11), and no style tab or style group", function()
        H.Hekili:EmbedDisplayOptions()
        local page = H.Hekili.Options.args.displays.args.barGlow
        assert.is_table(page)
        assert.are.equal("group", page.type)
        assert.is_nil(H.Hekili.Options.args.barGlow) -- not a top-level page any more
        assert.is_table(H.Hekili.Options.args.displays.args.barGlowBtn) -- the overview's shortcut, like Share Styles
        for _, k in ipairs({ "enabled", "follow", "colorNow", "glowNext", "colorNext", "combatOnly" }) do
            assert.is_table(page.args[k], k)
        end
        assert.is_nil(H.ns.StyleOptions.barGlow)
        for _, style in ipairs({ "classic", "timeline" }) do
            assert.is_nil(H.ns.UI.Styles[style].defaults.barGlow)
        end
        H.Hekili:EmbedDisplayOptions()
        assert.is_nil(H.Hekili.Options.args.displays.plugins.Primary.Primary.args.classic.args.barGlow)
    end)

    it("subscribes actively to the followed stream while enabled, and moves with the setting", function()
        assert.is_true(active("Primary"))
        assert.is_false(active("AOE"))
        cfg.follow = "AOE"
        BG.Apply()
        assert.is_false(active("Primary"))
        assert.is_true(active("AOE"))
        cfg.enabled = false
        BG.Apply()
        assert.is_false(active("AOE"))
        cfg.enabled, cfg.follow = true, "NoSuchDisplay"
        BG.Apply() -- an unknown display: no subscription, no error
        assert.is_false(active("AOE"))
    end)

    it("clears its glows when the followed display changes", function()
        local e = bars()
        put("mortal_strike", "overpower")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        cfg.follow = "AOE"
        BG.Apply()
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it("asks the engine to compute the stream and glows with every display hidden", function()
        local e = bars()
        local profile = H.Hekili.DB.profile
        for _, display in pairs(profile.displays) do
            display.enabled = false
        end
        H.Hekili:UpdateDisplayVisibility()
        assert.is_true(H.ns.Output.Wanted("Primary")) -- only our active subscription wants it
        put("mortal_strike", "overpower")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
    end)

    it("glows in combat only by default: lit on entering combat, cleared on leaving it", function()
        local e = bars()
        cfg.combatOnly = true
        H.ctl.combat = false
        BG.Apply()
        put("mortal_strike", "overpower")
        assert.is_nil(glow.on(e.ActionButton1))
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.are.same(NOW, (glow.on(e.ActionButton1)))
        assert.are.same(NEXT, (glow.on(e.ActionButton2)))
        H.ctl.combat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.is_nil(glow.on(e.ActionButton1))
        assert.is_nil(glow.on(e.ActionButton2))
    end)

    it(
        "loads and draws a profile that still holds SpellFlash's old settings, and the per-style glow keys, and offers no such tab",
        function()
            local old = { enabled = true, color = { 1, 0, 0, 1 }, suppress = true, size = 111, combat = true }
            local saved = {
                profiles = {
                    Default = {
                        flashTexture = "Interface\\Cooldown\\ping4",
                        displays = {
                            Primary = {
                                flash = old,
                                classic = { flash = old, barGlow = { enabled = true } },
                                timeline = { flash = old, barGlow = { enabled = true, colorNow = { 0, 1, 0, 1 } } },
                            },
                        },
                    },
                },
            }
            install()
            local H2 = headless.new({ character = ww.character(), pack = ww.PACK, saved = saved })
            fake.new = fakeNew
            assert.are.same({}, H2.loadErrors)
            assert(headless.cycle(H2, H2.ctl.now + 0.2))
            local conf = H2.Hekili.DB.profile.displays.Primary
            local dsp = rawget(H2.env, "HekiliDisplayPrimary")
            for _, style in ipairs({ "classic", "timeline", "classic" }) do
                conf.style = style
                H2.Hekili:BuildUI()
                local abilities = H2.Hekili.Engine.Registry.Abilities()
                local o = H2.ns.Output.Begin("Primary")
                for n, a in ipairs({ "mortal_strike", "overpower" }) do
                    o[n].actionName, o[n].actionID, o[n].texture = a, abilities[a].id, "tex" .. n
                    o[n].time, o[n].exact_time = n, H2.ctl.now + n
                end
                H2.ns.Output.Publish("Primary", 2)
                for _ = 1, 3 do
                    H2.ctl.now = H2.ctl.now + 0.2
                    dsp.__scripts.OnUpdate(dsp, 0.2)
                end
            end
            assert.are.same({}, H2.errors)
            H2.Hekili:EmbedDisplayOptions()
            local args = H2.Hekili.Options.args.displays.plugins.Primary.Primary.args.classic.args
            assert.is_nil(args.flash)
            assert.is_nil(args.barGlow)
            assert.is_false(H2.Hekili.DB.profile.barGlow.enabled) -- the per-style keys are ignored
        end
    )
end)
