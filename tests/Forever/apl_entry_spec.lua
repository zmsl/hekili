-- tests/Forever/apl_entry_spec.lua (central fix 2, gap 5): a priority with no precombat list (every wowsims list
-- without prepull actions) is a first-class case: GetNextPrediction starts from the forecast window, so the default
-- list runs and recommends in and out of combat, and nothing raises.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("a priority without a precombat list", function()
    it("recommends out of combat and in combat without raising", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            default = { { enabled = true, action = "berserker_stance" } },
        }
        H.Hekili:LoadScripts()
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        assert.are.equal("berserker_stance", out.recs[1] and out.recs[1].actionName)
        H.Fire("PLAYER_REGEN_DISABLED")
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        assert.are.equal("berserker_stance", out.recs[1] and out.recs[1].actionName)
    end)
end)
