-- tests/Forever/combo_refresh_spec.lua: core's power handler forces one refresh when the player's combo points change
-- (UNIT_POWER_FREQUENT with the "COMBO_POINTS" token), end to end with a real pack loaded, and none for an energy tick.
local headless = require("Game.harness.headless")
local w = require("Forever.helpers.rogue_world")

describe("combo point refresh", function()
    it("core forces exactly one update for COMBO_POINTS and none for ENERGY", function()
        local H = headless.new({ character = w.Combat.character(), pack = w.Combat.PACK })
        assert.are.same({}, H.loadErrors)
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
        local forced = {}
        H.Hekili.ForceUpdate = function(_, event, super)
            forced[#forced + 1] = tostring(event) .. ":" .. tostring(super)
        end
        H.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
        assert.are.same({}, forced)
        H.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        assert.are.same({ "UNIT_POWER_FREQUENT:true" }, forced) -- the whole list: a pack hook beside core's fails here
        assert.are.same({}, H.errors)
    end)
end)
