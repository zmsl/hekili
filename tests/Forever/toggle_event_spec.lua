-- tests/Forever/toggle_event_spec.lua: the public toggle state, HEKILI_TOGGLE (a WeakAuras event) and
-- Hekili:GetToggleState (src/Hekili/Options/Options.lua, ChatCommands.lua). The event fires only for an accepted change,
-- with the toggle's new state (never the typed word of a rejected mode), and on pause; its value is always what
-- GetToggleState answers.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("HEKILI_TOGGLE and GetToggleState (headless Arms)", function()
    local H, hk, fired

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        hk = H.Hekili
        hk.Engine.settings.screenshot = false -- the harness has no Screenshot()
        hk.DB.profile.notifications.enabled = false
        assert(headless.cycle(H, H.ctl.now + 0.2))
        fired = {}
        H.env.WeakAuras = {
            ScanEvents = function(event, name, value)
                if event == "HEKILI_TOGGLE" then
                    fired[#fired + 1] = { name, value }
                end
            end,
        }
    end)

    after_each(function()
        H.env.WeakAuras = nil
    end)

    it("a rejected /hekili set mode fires nothing and keeps the mode; an accepted one fires the stored mode", function()
        local mode = hk:GetToggleState("mode")
        hk:CmdLine("set mode bogus")
        assert.are.same({}, fired)
        assert.are.equal(mode, hk:GetToggleState("mode"))
        hk:CmdLine("set mode AOE")
        assert.are.same({ { "mode", "aoe" } }, fired)
        assert.are.equal("aoe", hk:GetToggleState("mode"))
    end)

    it("FireToggle fires nothing for a rejected mode or state, and the new state for an accepted one", function()
        hk:FireToggle("mode", "bogus")
        hk:FireToggle("cooldowns", "maybe")
        assert.are.same({}, fired)
        hk:FireToggle("cooldowns", "off")
        assert.are.same({ { "cooldowns", false } }, fired)
        assert.is_false(hk:GetToggleState("cooldowns"))
    end)

    it("pause fires with the paused state, which GetToggleState answers", function()
        assert.is_false(hk:GetToggleState("pause"))
        hk:FireToggle("pause")
        assert.are.same({ { "pause", true } }, fired)
        assert.is_true(hk:GetToggleState("pause"))
        hk:TogglePause()
        assert.are.same({ "pause", false }, fired[2])
        assert.is_false(hk:GetToggleState("pause"))
    end)

    it("a profile refresh fires every toggle that has a state, each with GetToggleState's answer", function()
        hk:TotalRefresh()
        assert.is_true(#fired > 0)
        local seen = {}
        for _, f in ipairs(fired) do
            assert.is_not_nil(f[2], f[1])
            assert.are.equal(hk:GetToggleState(f[1]), f[2], f[1])
            seen[f[1]] = true
        end
        assert.is_true(seen.pause)
        assert.is_true(seen.mode)
        assert.is_nil(seen.snapshot)
    end)
end)
