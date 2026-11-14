-- tests/Forever/prev_last_spec.lua: `prev.last` (and `prev.<ability>`) answer the last ability cast, like
-- `prev_gcd.last` and `prev_off_gcd.last` do (State.lua mt_prev); a misspelt meta name left it "none" for prev.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("prev.last", function()
    it("answers the last cast after a reset, as prev_gcd.last does", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local S = H.Hekili.State
        S.player.lastcast, S.player.lastgcd = "slam", "slam"
        S.reset("Primary", true)
        assert.are.equal("slam", S.prev_gcd.last)
        assert.are.equal("slam", S.prev.last)
        assert.is_true(S.prev.slam)
        assert.is_false(S.prev.whirlwind)
    end)
end)
