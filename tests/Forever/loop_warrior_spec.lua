-- tests/Forever/loop_warrior_spec.lua (headless loop design §5, §7, §9): stock Hekili headless as a level 60 Arms
-- Warrior (tests/Forever/helpers/warrior_world.lua) against the harness's world.
local headless = require("Virtual.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("headless Arms", function()
    it("boots the Arms character: three entries out of combat with a target, no error, no unlisted nil read", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert.are.equal(ww.SPEC, H.Hekili.State.spec.id)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        local q = H.ns.UI.Displays.Primary.Recommendations
        for i = 1, 3 do
            assert.is_table(H.Hekili.Class.abilities[q[i].actionName], tostring(q[i].actionName))
        end
        assert.are.same({}, H.errors)
        assert.are.same({}, headless.unexpected(H, "run"))
    end)
end)
