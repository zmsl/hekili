-- target.time_to_pct_<N> answers the same unknown time as time_to_die and fight_remains: 3600.
local headless = require("Game.harness.headless")
local wl = require("Forever.helpers.warlock_world")

describe("time to pct, unknown target time to die", function()
    it("answers 3600, as every other unknown time does", function()
        local H = headless.new({ character = wl.Destruction.character(), pack = wl.Destruction.PACK })
        assert.are.same({}, H.loadErrors)
        assert.are.equal(3600, H.Hekili:GetTimeToPct("target", 20))
        assert.are.equal(3600, H.Hekili:GetTimeToPct("target", 0.2))
    end)
end)
