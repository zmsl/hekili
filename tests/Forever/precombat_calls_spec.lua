-- tests/Forever/precombat_calls_spec.lua: "in precombat" is a property of the walk (Engine/Sim/Core.lua's
-- GetPredictionFromAPL), not of a list's name: a list the precombat list calls (wowsims's "Pre-pull: Move" becomes
-- `pre_pull_move`) is filtered in combat like precombat itself, at any depth, while the same list reached from the
-- default list is not. Defensive Stance stands in for any action usable in and out of combat.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("a list called from precombat", function()
    local H, t, out

    local function cycle()
        t = t + 0.2
        H.ctl.now = t
        assert(headless.cycle(H, t))
        return out.count > 0 and out.recs[1].actionName or false
    end

    local function call(name)
        return { enabled = true, action = "call_action_list", list_name = name }
    end
    local stance = { enabled = true, action = "defensive_stance", use_off_gcd = 1 }

    local function lists(l)
        H.Hekili.DB.profile.packs[ww.PACK].lists = l
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks() -- the new lists active
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK }) -- in Battle Stance
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now
        out = H.Hekili.Engine.Output.Primary
        cycle()
    end)

    it("is recommended out of combat and never in combat", function()
        lists({ precombat = { call("pre_pull") }, pre_pull = { stance }, default = {} })
        assert.are.equal("defensive_stance", cycle())
        H.Fire("PLAYER_REGEN_DISABLED")
        for _ = 1, 5 do
            assert.is_false(cycle())
        end
        assert.are.same({}, H.errors)
    end)

    it("is filtered in combat two calls deep", function()
        lists({ precombat = { call("outer") }, outer = { call("inner") }, inner = { stance }, default = {} })
        assert.are.equal("defensive_stance", cycle())
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_false(cycle())
        assert.are.same({}, H.errors)
    end)

    it("schedules its prepull_at entries as precombat's own: once an episode", function()
        local once = { enabled = true, action = "defensive_stance", use_off_gcd = 1, prepull_at = 1 }
        lists({ precombat = { call("pre_pull") }, pre_pull = { once }, default = {} })
        assert.are.equal("defensive_stance", cycle())
        t = t + 1.6
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-ds", H.Hekili.Class.abilities.defensive_stance.id)
        H.ctl.form = ww.FORM.defensive_stance
        H.Fire("UPDATE_SHAPESHIFT_FORM")
        H.ctl.form = ww.FORM.battle_stance -- back in Battle Stance: a plain entry would be offered again
        H.Fire("UPDATE_SHAPESHIFT_FORM")
        assert.is_false(cycle())
        assert.are.same({}, H.errors)
    end)

    it("is still recommended in combat when the default list reaches it", function()
        lists({ precombat = { call("shared") }, shared = { stance }, default = { call("shared") } })
        assert.are.equal("defensive_stance", cycle())
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.are.equal("defensive_stance", cycle())
        assert.are.same({}, H.errors)
    end)
end)
