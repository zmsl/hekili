-- tests/Forever/belief_log_spec.lua (border batch 3, item 1): the core injects its logger into the belief through
-- VS.SetLog and opens each display's snapshot log with the belief's own Snapshot() itself; Hekili.Virtual (the
-- debug bridge ForeverProbe reads) is set by the core.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the belief's logger", function()
    local H

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
    end)

    it(
        "Hekili:SetupDebug opens a display's log with the belief's Snapshot() while debugging, never otherwise",
        function()
            local hk, lines = H.Hekili, {}
            local debug = hk.Debug
            hk.Debug = function(_, fmt, ...)
                lines[#lines + 1] = string.format(fmt, ...)
            end
            hk:SetupDebug("Primary")
            assert.are.same({}, lines)
            hk.ActiveDebug = true
            hk:SetupDebug("Primary")
            hk:SetupDebug(nil)
            hk.ActiveDebug = false
            hk.Debug = debug
            local opened = 0
            for _, l in ipairs(lines) do
                if l:find("VirtualState t=", 1, true) == 1 then
                    opened = opened + 1
                end
            end
            assert.are.equal(1, opened)
        end
    )

    it("the facade's trace writes through the injected logger only while debugging", function()
        local hk, lines = H.Hekili, {}
        hk.Debug = function(_, fmt, ...)
            lines[#lines + 1] = string.format(fmt, ...)
        end
        hk.Client.UnitName("player")
        assert.are.same({}, lines)
        hk.ActiveDebug = true
        hk.Client.UnitName("player")
        hk.ActiveDebug = false
        assert.are.equal(1, #lines)
        assert.is_truthy(lines[1]:find("[vs] ", 1, true))
    end)

    it("Hekili.Virtual is the core's debug bridge to the belief", function()
        local hk, ns = H.Hekili, H.ns
        assert.are.equal(ns.VirtualState, hk.Virtual.State)
        assert.are.equal(ns.VirtualStateInternal.Events, hk.Virtual.Events)
        assert.are.equal(ns.VirtualStateInternal.Prof, hk.Virtual.Prof)
        assert.is_function(hk.Virtual.State.Snapshot)
    end)
end)
