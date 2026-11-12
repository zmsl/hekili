-- tests/Forever/target_targeting_spec.lua: `target.is_targeting_player`, UnitIsUnit("targettarget", "player") through
-- the facade, on the real engine's target table: a secret or unknown answer is false (L602).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local SECRET = require("Game.State.helpers.fake_api").SECRET

describe("the target's is_targeting_player", function()
    local H, t

    local function cycle(tt) -- the client's targettarget answer from now on, then one refresh
        H.ctl.unitIs.targettarget = tt
        t = t + 0.2
        H.ctl.now = t
        assert(headless.cycle(H, t))
        return H.Hekili.State.target.is_targeting_player
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now
    end)

    it("is true while the target targets us, false otherwise, secret or unknown", function()
        assert.is_true(cycle("player"))
        assert.is_false(cycle(nil)) -- someone else, or no target of target
        assert.is_true(cycle("player")) -- re-read each refresh, never kept
        assert.is_false(cycle(SECRET))
        assert.is_false(cycle("party1"))
        assert.are.same({}, H.errors)
    end)
end)
