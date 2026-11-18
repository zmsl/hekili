-- tests/Forever/dominos_bindings_spec.lua: the Dominos branch of the keybinding reader (Engine/Sim/Events.lua,
-- ns.ReadKeybindings) with some of DominosFrame1..14 missing (a Dominos setup may not create every bar). A missing
-- frame or frame without buttons is skipped; slots Dominos does not claim fall back to the default UI bars.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

local world

local fakeNew = fake.new
local function boot()
    fake.new = function(...)
        local api, ctl = fakeNew(...)
        api.GetActionInfo = function(slot)
            local id = world.actions[slot]
            if id then
                return "spell", id
            end
        end
        api.GetBindingKey = function(command)
            return world.keys[command]
        end
        return api, ctl
    end
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    fake.new = fakeNew
    assert.are.same({}, H.loadErrors)
    H.ns.Facade.C_AddOns.IsAddOnLoaded = function(name)
        return name == "Dominos"
    end
    return H
end

local function id(H, name)
    return H.Hekili.Engine.Registry.Abilities()[name].id
end

local function button(action)
    return {
        action = action,
        GetName = function()
            return "TestButton" .. action
        end,
    }
end

describe("Dominos keybinding discovery", function()
    before_each(function()
        world = { actions = {}, keys = {} }
    end)

    it("reads Dominos bars 1-8 and the default bars for the rest when bars 9-14 do not exist", function()
        local H = boot()
        world.actions[5], world.actions[2] = id(H, "mortal_strike"), id(H, "overpower")
        world.keys.ACTIONBUTTON5, world.keys.ACTIONBUTTON2 = "SHIFT-5", "SHIFT-2"
        for i = 1, 8 do
            H.env["DominosFrame" .. i] = { buttons = {} }
        end
        H.env.DominosFrame3.buttons[1] = button(5) -- Dominos shows slot 5 on bar 3 (the default fallback would say bar 1)
        H.env.DominosFrame2 = {} -- a frame without a button collection
        assert.has_no.errors(function()
            H.ns.ReadKeybindings()
        end)
        local info = H.Hekili.KeybindInfo
        assert.are.equal("S5", info.mortal_strike.upper[3]) -- Dominos' own binding, on Dominos' bar
        assert.is_nil(info.mortal_strike.upper[1]) -- slot 5 is claimed: no default-bar copy
        assert.are.equal("S2", info.overpower.upper[1]) -- slot 2 is not claimed: the default bar's binding
    end)

    it("does not raise with no Dominos frame at all", function()
        local H = boot()
        assert.has_no.errors(function()
            H.ns.ReadKeybindings()
        end)
    end)
end)
