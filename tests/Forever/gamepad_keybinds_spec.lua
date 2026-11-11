-- tests/Forever/gamepad_keybinds_spec.lua: Forever's native gamepad action bars on Hekili's icons. The reader
-- (Engine/Sim/Events.lua, ns.Gamepad) turns storage slots 181+ into (page, bar, position), reads the buttons and
-- modifier keys at runtime and stores the controller pictures per ability; a pad key on a normal bar becomes a picture
-- too; the classic and timeline styles put a gamepad binding outside the icon (UI.SetKeybindingText).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

-- The fake client's gamepad side, one table the tests edit: action ids by slot, binding keys by command.
local world

local fakeNew = fake.new
local function install()
    fake.new = function(...)
        local api, ctl = fakeNew(...)
        api.GetActionInfo = function(slot)
            local id = world.actions[slot]
            if id then
                return "spell", id
            end
        end
        api.GetBindingKey = function(command, override)
            -- gamepad mode binds its buttons as override bindings: a plain read may answer nothing (owner, in game)
            if world.overrideOnly and not override and command:find("^GAMEPAD") then
                return nil
            end
            return world.keys[command]
        end
        api.C_GamepadUI.GetFirstGamepadActionStorageSlotIndex = function()
            return world.first
        end
        api.C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance = function()
            return world.formBase
        end
        api.C_ActionBar.HasBonusActionBar = function()
            return world.bonus
        end
        api.InputDeviceIconSetManager = {
            GetActiveInputDeviceIconSet = function()
                return world.set
            end,
        }
        return api, ctl
    end
end

local BUTTON = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" } -- the owner's, measured

local function reset()
    world = { actions = {}, keys = {}, first = 181, bonus = false, formBase = nil, set = "Letters" }
    for pos, key in ipairs(BUTTON) do
        world.keys["GAMEPADACTIONBUTTON" .. pos] = key
    end
    world.keys.GAMEPADLEFTMOD, world.keys.GAMEPADRIGHTMOD = "PADLTRIGGER", "PADRTRIGGER"
end

local function glyphs(H, set)
    local e = H.env
    for _, key in ipairs({ "PADDLEFT", "PADDUP", "PADLTRIGGER", "PADRTRIGGER", "PAD1" }) do
        e["KEY_ABBR_" .. key .. "_LTR"] = "|A:Gamepad_Ltr_" .. key .. "_32:14:14|a"
        e["KEY_ABBR_" .. key] = "|A:Gamepad_Gen_" .. key .. "_32:14:14|a"
    end
    e.Enum = {
        GamepadStanceBarOverride = {
            None = 0,
            Page1TopBar = 1,
            Page1LeftBar = 2,
            Page1RightBar = 3,
            Page1BottomBar = 4,
        },
    }
end

local function boot()
    install()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    fake.new = fakeNew
    assert.are.same({}, H.loadErrors)
    glyphs(H)
    return H
end

local function id(H, name)
    return H.Hekili.Engine.Registry.Abilities()[name].id
end

local function read(H)
    H.ns.ReadKeybindings()
    return H.Hekili.KeybindInfo
end

local function L(key, size)
    return "|A:Gamepad_Ltr_" .. key .. "_32:" .. (size or 14) .. ":" .. (size or 14) .. "|a"
end
local function G(key)
    return "|A:Gamepad_Gen_" .. key .. "_32:14:14|a"
end

describe("gamepad keybinds", function()
    before_each(reset)

    it("maps a storage slot to page, bar and position", function()
        local H = boot()
        local slot = H.ns.Gamepad.Slot
        local function at(n)
            local page, bar, pos = slot(n, 181)
            return { page, bar, pos }
        end
        assert.are.same({ 1, 1, 1 }, at(181)) -- top bar, d-pad left
        assert.are.same({ 1, 1, 4 }, at(184))
        assert.are.same({ 1, 2, 1 }, at(185)) -- left bar
        assert.are.same({ 1, 2, 8 }, at(192))
        assert.are.same({ 1, 3, 1 }, at(193)) -- right bar
        assert.are.same({ 1, 4, 1 }, at(201)) -- bottom bar
        assert.are.same({ 1, 4, 8 }, at(208))
        assert.are.same({ 2, 2, 3 }, at(181 + 28 + 6)) -- page 2, left bar, position 3
        assert.is_nil(slot(180, 181))
        assert.is_nil(slot(181 + 84, 181)) -- past the three standard pages
    end)

    it("shows the left trigger and the d-pad picture for an action at 186, in the player's controller style", function()
        local H = boot()
        world.actions[186] = id(H, "mortal_strike")
        local info = read(H)
        assert.are.equal(L("PADLTRIGGER") .. L("PADDUP"), info.mortal_strike.pad[1])
        -- no _LTR global for the button: the generic one stands in
        H.env.KEY_ABBR_PADDUP_LTR = nil
        info = read(H)
        assert.are.equal(L("PADLTRIGGER") .. G("PADDUP"), info.mortal_strike.pad[1])
        -- neither: readable text
        H.env.KEY_ABBR_PADDUP = nil
        info = read(H)
        assert.are.equal(L("PADLTRIGGER") .. "Up", info.mortal_strike.pad[1])
        -- Generic: as Blizzard's own gamepad bars draw it (the Xbox letters, ActionBarButton.lua:45-82), not the numbered
        -- generic key names (in game: '3' for X); the generic picture still stands in where no letters one exists
        world.set = "Generic"
        H.env.KEY_ABBR_PADDUP = G("PADDUP")
        assert.are.equal(L("PADLTRIGGER") .. G("PADDUP"), read(H).mortal_strike.pad[1])
        assert.are.equal(L("PAD1"), H.ns.Gamepad.Glyph("PAD1"))
        -- no modifier on the top bar, both on the bottom bar
        world.set = "Letters"
        H.env.KEY_ABBR_PADDUP_LTR = L("PADDUP")
        world.actions = { [182] = id(H, "mortal_strike"), [201] = id(H, "overpower") }
        info = read(H)
        assert.are.equal(L("PADDUP"), info.mortal_strike.pad[1])
        assert.are.equal(L("PADLTRIGGER") .. L("PADRTRIGGER") .. L("PADDLEFT"), info.overpower.pad[1])
    end)

    it("reads the gamepad buttons and modifiers as override bindings (a plain read answers nothing)", function()
        local H = boot()
        world.overrideOnly = true
        world.actions[194] = id(H, "mortal_strike") -- right bar, d-pad up: the owner's Faerie Fire slot
        assert.are.equal(L("PADRTRIGGER") .. L("PADDUP"), read(H).mortal_strike.pad[1])
    end)

    it("reads nothing without the gamepad action bars", function()
        local H = boot()
        world.actions[186] = id(H, "mortal_strike")
        world.first = nil
        local info = read(H)
        assert.are.same({}, info.mortal_strike and info.mortal_strike.pad or {})
        -- and the keyboard path is untouched
        world.keys.ACTIONBUTTON1 = "SHIFT-1"
        world.actions[1] = id(H, "mortal_strike")
        assert.are.equal("S1", read(H).mortal_strike.upper[1])
    end)

    describe("the form bar", function()
        it(
            "replaces the bar the CVar names: the form slot takes its modifier, the bar's own slots are not offered",
            function()
                local H = boot()
                H.ctl.cvars.GamepadStanceBarOverride = "2" -- Page1LeftBar
                world.bonus, world.formBase = true, 265
                world.actions[265 + 1] = id(H, "mortal_strike") -- form slot 2 = d-pad up
                world.actions[186] = id(H, "overpower") -- the replaced left bar
                local info = read(H)
                assert.are.equal(L("PADLTRIGGER") .. L("PADDUP"), info.mortal_strike.pad[1])
                assert.is_nil(info.overpower and info.overpower.pad[1])
                -- off the form, the left bar is offered again
                world.bonus = false
                info = read(H)
                assert.is_nil(info.mortal_strike.pad[1])
                assert.are.equal(L("PADLTRIGGER") .. L("PADDUP"), info.overpower.pad[1])
            end
        )

        it("ignores the form bar when the override is None", function()
            local H = boot()
            H.ctl.cvars.GamepadStanceBarOverride = "0"
            world.bonus, world.formBase = true, 265
            world.actions[266] = id(H, "mortal_strike")
            world.actions[186] = id(H, "overpower")
            local info = read(H)
            assert.is_nil(info.mortal_strike and info.mortal_strike.pad[1])
            assert.are.equal(L("PADLTRIGGER") .. L("PADDUP"), info.overpower.pad[1])
        end)

        it("offers nothing for the replaced right bar while an empty form bar shows", function()
            local H = boot()
            H.ctl.cvars.GamepadStanceBarOverride = "3" -- Page1RightBar, the owner's
            world.bonus, world.formBase = true, 265 -- slots 265-272 hold nothing
            world.actions[193] = id(H, "mortal_strike") -- right bar, position 1
            world.actions[200] = id(H, "overpower") -- right bar, position 8
            world.actions[185] = id(H, "slam") -- the left bar stays
            local info = read(H)
            assert.is_nil(info.mortal_strike and info.mortal_strike.pad[1])
            assert.is_nil(info.overpower and info.overpower.pad[1])
            assert.are.equal(L("PADLTRIGGER") .. L("PADDLEFT"), info.slam.pad[1])
        end)
    end)

    it("renders a pad key on a normal bar as its picture, not as abbreviated text", function()
        local H = boot()
        world.keys.ACTIONBUTTON1, world.keys.ACTIONBUTTON2 = "SHIFT-PADDLEFT", "PAD1"
        world.actions[1], world.actions[2] = id(H, "mortal_strike"), id(H, "overpower")
        local info = read(H)
        assert.are.equal("S" .. L("PADDLEFT"), info.mortal_strike.upper[1])
        assert.are.equal("S" .. L("PADDLEFT"), info.mortal_strike.lower[1]) -- markup is case-sensitive
        assert.are.equal(L("PAD1"), info.overpower.upper[1])
        assert.is_nil(tostring(info.mortal_strike.upper[1]):find("PADDDn", 1, true))
        -- a keyboard binding with no pad key reads as before
        world.keys.ACTIONBUTTON1 = "ALT-DOWN"
        assert.are.equal("ADn", read(H).mortal_strike.upper[1])
        -- a number-pad key holds "PAD" inside a word: still keyboard text, lower-cased as before
        world.keys.ACTIONBUTTON1 = "CTRL-NUMPAD1"
        local np = read(H).mortal_strike
        assert.are.equal("CN1", np.upper[1])
        assert.are.equal("cn1", np.lower[1])
    end)

    it("re-reads once the controller style is known when it was not at the first read (in game: '3' for X)", function()
        local H = boot()
        world.set = nil -- right after login the game has not reported the style yet: the generic pictures
        world.actions[186] = id(H, "mortal_strike")
        read(H)
        local conf = H.Hekili.DB.profile.displays.Primary
        conf.classic.gamepad.size = 14
        assert.are.equal(G("PADLTRIGGER") .. G("PADDUP"), H.Hekili:GetBindingForAction("mortal_strike", conf, 1))
        world.set = "Letters" -- the style arrives: the next answer schedules a re-read
        H.Hekili:GetBindingForAction("mortal_strike", conf, 1)
        H.RunTimers(H.ctl.now + 1)
        assert.are.equal(L("PADLTRIGGER") .. L("PADDUP"), H.Hekili:GetBindingForAction("mortal_strike", conf, 1))
    end)

    it("answers the gamepad text (sized to the font) in place of keyboard text; an override still wins", function()
        local H = boot()
        world.keys.ACTIONBUTTON1 = "5"
        world.actions[1], world.actions[186] = id(H, "mortal_strike"), id(H, "mortal_strike")
        read(H)
        local conf = H.Hekili.DB.profile.displays.Primary
        conf.classic.keybindings.fontSize = 33 -- the keyboard font does not size the pictures
        conf.classic.gamepad.size = 20
        local text = H.Hekili:GetBindingForAction("mortal_strike", conf, 1)
        assert.are.equal(L("PADLTRIGGER", 20) .. L("PADDUP", 20), text)
        assert.is_true(H.ns.Gamepad.Is(text))
        assert.is_false(H.ns.Gamepad.Is("5"))
        -- without a gamepad binding: the keyboard text
        world.actions[186] = nil
        read(H)
        assert.are.equal("5", H.Hekili:GetBindingForAction("mortal_strike", conf, 1))
        -- a per-ability override beats both
        world.actions[186] = id(H, "mortal_strike")
        read(H)
        local spec = H.Hekili.Engine.settings.specs[H.Hekili.State.spec.id]
        spec.abilities.mortal_strike.keybind = "F9"
        assert.are.equal("F9", H.Hekili:GetBindingForAction("mortal_strike", conf, 1))
        spec.abilities.mortal_strike.keybind = nil
    end)
end)

-- A font string that records what the styles do to it.
local function fs()
    local f = { points = {} }
    function f:ClearAllPoints()
        self.points = {}
    end
    function f:SetPoint(...)
        self.points[#self.points + 1] = { ... }
    end
    function f:SetJustifyH(v)
        self.h = v
    end
    function f:SetJustifyV(v)
        self.v = v
    end
    function f:GetJustifyV()
        return self.v or "MIDDLE"
    end
    function f:SetText(t)
        self.text = t
    end
    return f
end

describe("gamepad keybinds on the icons", function()
    before_each(reset)

    local function setup(style)
        local H = boot()
        world.actions[186] = id(H, "mortal_strike")
        world.keys.ACTIONBUTTON1 = "5"
        world.actions[1] = id(H, "overpower")
        read(H)
        local conf = H.Hekili.DB.profile.displays.Primary
        conf.style = style
        conf.numIcons = 6
        H.Hekili:BuildUI()
        local d = rawget(H.env, "HekiliDisplayPrimary")
        return H, d, conf
    end

    it("anchors a gamepad binding below the classic icon, above with Top; keyboard text keeps its anchor", function()
        local H, d, conf = setup("classic")
        local kb, g = conf.classic.keybindings, conf.classic.gamepad
        -- by default the pictures sit where keyboard text sits
        assert.are.same({ anchor = kb.anchor, x = kb.x, y = kb.y, size = 12 }, g)
        assert.is_nil(kb.gamepadPosition)
        kb.anchor, kb.x, kb.y = "BOTTOMLEFT", 3, 4 -- the keyboard text moves, the pictures' own anchor does not
        local b1, b2 = d.Buttons[1], d.Buttons[2]
        b1.Keybinding, b2.Keybinding = fs(), fs()
        b1.Action, b2.Action = "mortal_strike", "overpower"
        d.style.UpdateKeybindings(d)
        assert.is_true(H.ns.Gamepad.Is(b1.Keybinding.text))
        assert.are.same({ { "TOPRIGHT", b1, "TOPRIGHT", 1, -1 } }, b1.Keybinding.points)
        assert.are.equal("RIGHT", b1.Keybinding.h)
        assert.are.equal("5", b2.Keybinding.text) -- keyboard text: its own anchor
        assert.are.same({ { "BOTTOMLEFT", b2, "BOTTOMLEFT", 3, 4 } }, b2.Keybinding.points)
        -- changing the gamepad anchor and offsets moves it; an unchanged refresh sets no point again
        g.anchor, g.x, g.y = "BOTTOM", -2, 6
        d.style.UpdateKeybindings(d)
        assert.are.same({ { "BOTTOM", b1, "BOTTOM", -2, 6 } }, b1.Keybinding.points)
        assert.are.equal("CENTER", b1.Keybinding.h)
        b1.Keybinding.points[1].marker = true
        d.style.UpdateKeybindings(d)
        assert.is_true(b1.Keybinding.points[1].marker)
        -- the ability loses its gamepad binding: back to the keyboard anchor
        world.actions[186] = nil
        read(H)
        d.style.UpdateKeybindings(d)
        assert.are.same({ { kb.anchor, b1, kb.anchor, kb.x, kb.y } }, b1.Keybinding.points)
    end)

    it(
        "shows gamepad pictures on the timeline's now circle and next box only; keyboard text stays off a focus",
        function()
            local H, d, conf = setup("timeline")
            local T = d.styleFrames.timeline
            local kb = conf.timeline.keybindings
            for c = 1, 3 do
                T.cells[c].Keybinding = fs()
                T.cells[c].Action = c == 3 and "overpower" or "mortal_strike"
                T.rec[c] = c
            end
            T.cells[3].Action = "mortal_strike" -- same gamepad ability in the lane
            T.focused = false
            d.style.UpdateKeybindings(d)
            assert.is_true(H.ns.Gamepad.Is(T.cells[1].Keybinding.text))
            assert.is_true(H.ns.Gamepad.Is(T.cells[2].Keybinding.text))
            assert.is_nil(T.cells[3].Keybinding.text) -- never on a lane record
            local g = conf.timeline.gamepad
            assert.are.same({ { g.anchor, T.cells[1], g.anchor, g.x, g.y } }, T.cells[1].Keybinding.points)
            assert.are.same({ g.anchor, g.x, g.y }, { kb.anchor, kb.x, kb.y }) -- the defaults agree
            g.anchor, g.x, g.y = "BOTTOMLEFT", 5, 6
            d.style.UpdateKeybindings(d)
            assert.are.same({ { "BOTTOMLEFT", T.cells[2], "BOTTOMLEFT", 5, 6 } }, T.cells[2].Keybinding.points)
            -- a focus record on cell 1: the picture still shows (keyboard text would not)
            T.focused, T.rec[1] = true, 2 -- a focus record (not the first pick) holds the circle
            d.style.UpdateKeybindings(d)
            assert.is_true(H.ns.Gamepad.Is(T.cells[1].Keybinding.text))
            T.cells[1].Action = "overpower"
            d.style.UpdateKeybindings(d)
            assert.is_nil(T.cells[1].Keybinding.text) -- keyboard text on a focus: none
            T.cells[3].Action = "overpower"
            d.style.UpdateKeybindings(d)
            assert.are.equal("5", T.cells[3].Keybinding.text) -- keyboard text on the lane: as before
            assert.is_true(kb.enabled)
        end
    )
end)

describe("the Gamepad options tab", function()
    before_each(reset)

    local function tabs(H, style)
        H.Hekili:EmbedDisplayOptions()
        return H.Hekili.Options.args.displays.plugins.Primary.Primary.args[style].args
    end

    local function opt(H, style, path)
        local node = { args = tabs(H, style) }
        local info = { "displays", "Primary", style }
        for _, k in ipairs(path) do
            node = node.args[k]
            info[#info + 1] = k
        end
        info.option, info.arg = node, node.arg -- AceConfig passes both
        return node, info
    end

    it(
        "sizes the pictures from Size alone: the primary icon, classic's queued icons, the timeline's next box",
        function()
            local H = boot()
            world.actions[186] = id(H, "mortal_strike")
            read(H)
            local conf = H.Hekili.DB.profile.displays.Primary
            conf.classic.keybindings.separateQueueStyle, conf.classic.keybindings.queuedFontSize = true, 40
            conf.classic.gamepad.size = 18
            for i = 1, 2 do
                assert.are.equal(
                    L("PADLTRIGGER", 18) .. L("PADDUP", 18),
                    H.Hekili:GetBindingForAction("mortal_strike", conf, i)
                )
            end
            conf.style = "timeline"
            conf.timeline.keybindings.nextFontSize, conf.timeline.keybindings.fontSize = 40, 41
            conf.timeline.gamepad.size = 25
            for i = 1, 2 do
                assert.are.equal(
                    L("PADLTRIGGER", 25) .. L("PADDUP", 25),
                    H.Hekili:GetBindingForAction("mortal_strike", conf, i)
                )
            end
            local kb = H.ns.UI.Styles.timeline.defaults.keybindings
            assert.are.same(
                { anchor = kb.anchor, x = kb.x, y = kb.y, size = 12 },
                H.ns.UI.Styles.timeline.defaults.gamepad
            )
        end
    )

    it("exists in both styles; Keybinds is keyboard-only", function()
        local H = boot()
        for _, style in ipairs({ "classic", "timeline" }) do
            local t = tabs(H, style)
            local host = style == "classic" and t or t.tab_now.args -- the timeline's shared groups sit in its zone tabs
            assert.truthy(host.gamepad, style)
            assert.truthy(host.gamepad.args.pos.args.anchor)
            assert.truthy(host.gamepad.args.pos.args.x)
            assert.truthy(host.gamepad.args.pos.args.y)
            -- Size sits in the Position group: a loose slider after it drew over Y Offset (in game)
            assert.truthy(host.gamepad.args.pos.args.size)
            assert.is_nil(host.gamepad.args.size)
            assert.is_nil(host.gamepad.args.position) -- Top/Bottom and Offset are gone
            assert.is_nil(host.gamepad.args.offset)
            assert.truthy(host.gamepad.args.cPort.args.cPortOverride)
            assert.truthy(host.gamepad.args.cPort.args.cPortZoom)
            assert.is_nil(host.keybindings.args.cPort)
            assert.is_nil(host.keybindings.args.gamepad)
            assert.is_nil(host.keybindings.args.gamepadPosition)
        end
    end)

    it("keeps the ConsolePort options on the saved values they always used", function()
        local H = boot()
        local kb = H.Hekili.DB.profile.displays.Primary.classic.keybindings
        kb.cPortOverride, kb.cPortZoom = false, 0.25 -- a player's saved settings
        local _, io = opt(H, "classic", { "gamepad", "cPort", "cPortOverride" })
        local _, iz = opt(H, "classic", { "gamepad", "cPort", "cPortZoom" })
        assert.is_false(H.Hekili:GetDisplayOption(io))
        assert.are.equal(0.25, H.Hekili:GetDisplayOption(iz))
        H.Hekili.BuildUI = function() end
        H.Hekili:SetDisplayOption(io, true)
        H.Hekili:SetDisplayOption(iz, 0.9)
        assert.is_true(kb.cPortOverride)
        assert.are.equal(0.9, kb.cPortZoom)
        assert.is_nil(H.Hekili.DB.profile.displays.Primary.classic.gamepad.cPortZoom)
        -- the timeline's, too
        local tk = H.Hekili.DB.profile.displays.Primary.timeline.keybindings
        local _, it = opt(H, "timeline", { "tab_now", "gamepad", "cPort", "cPortZoom" })
        tk.cPortZoom = 0.3
        assert.are.equal(0.3, H.Hekili:GetDisplayOption(it))
        -- and the anchor lives in the gamepad group, not the keybindings'
        local _, ia = opt(H, "classic", { "gamepad", "pos", "anchor" })
        H.Hekili:SetDisplayOption(ia, "BOTTOM")
        assert.are.equal("BOTTOM", H.Hekili.DB.profile.displays.Primary.classic.gamepad.anchor)
        assert.are.equal("TOPRIGHT", kb.anchor)
    end)
end)
