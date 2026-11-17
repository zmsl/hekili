-- Exercise the actual Dominos branch without loading the simulation or a WoW client.
local file = assert(io.open("src/Hekili/Engine/Sim/Events.lua", "r"))
local source = file:read("*a")
file:close()
local branch = assert(source:match('elseif C_AddOns%.IsAddOnLoaded%("Dominos"%) then(.-)%-%- Use ElvUI'))

local function readBindings(frames)
    local stored, slotsUsed = {}, { [999] = true }
    local env = {
        _G = frames,
        table = {
            wipe = function(t)
                for k in pairs(t) do
                    t[k] = nil
                end
            end,
        },
        slotsUsed = slotsUsed,
        GetBindingKey = function(binding)
            return binding
        end,
        GetActionInfo = function(action)
            return "spell", action
        end,
        StoreKeybindInfo = function(page, binding, kind, action)
            stored[#stored + 1] = { page, binding, kind, action }
        end,
    }
    setfenv(assert(loadstring("if true then\n" .. branch .. "\nend")), env)()
    assert.is_nil(slotsUsed[999])
    return stored, slotsUsed
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
    it("allows Dominos to be loaded before any frames exist", function()
        assert.are.same({}, readBindings({}))
    end)

    it("skips frames without a button collection", function()
        assert.are.same({}, readBindings({ DominosFrame1 = {} }))
    end)

    it("skips missing buttons and buttons without an action", function()
        local stored = readBindings({ DominosFrame1 = { buttons = { [2] = {}, [3] = button(3) } } })
        assert.are.same({ { 1, "ACTIONBUTTON3", "spell", 3 } }, stored)
    end)

    it("reads eight initialized bars without requiring frames nine through fourteen", function()
        local frames = {}
        for i = 1, 8 do
            local buttons = {}
            for b = 1, 12 do
                buttons[b] = button((i - 1) * 12 + b)
            end
            frames["DominosFrame" .. i] = { buttons = buttons }
        end
        local stored, slotsUsed = readBindings(frames)
        assert.are.equal(96, #stored)
        assert.are.same({ 1, "ACTIONBUTTON1", "spell", 1 }, stored[1])
        assert.are.same({ 8, "CLICK TestButton96:HOTKEY", "spell", 96 }, stored[96])
        assert.is_true(slotsUsed[1])
        assert.is_true(slotsUsed[96])
    end)

    it("continues to later frames after missing frames", function()
        local stored, slotsUsed = readBindings({ DominosFrame14 = { buttons = { [12] = button(168) } } })
        assert.are.same({ { 14, "MULTIACTIONBAR7BUTTON12", "spell", 168 } }, stored)
        assert.is_true(slotsUsed[168])
    end)
end)
