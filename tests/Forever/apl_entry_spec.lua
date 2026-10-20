-- tests/Forever/apl_entry_spec.lua (central fix 2): what a priority may name and how it is entered. Gap 5: a priority
-- with no precombat list (every wowsims list without prepull actions) is a first-class case: GetNextPrediction starts
-- from the forecast window, so the default list runs and recommends in and out of combat, and nothing raises. Gap 7:
-- every race's racials are registered (Engine/Schema/Races.lua), another race's unknown, so a line naming one is
-- skipped as unknown. Gap 8: time to die answers "unknown" (Targets.lua's FOREVER, 3600 s) and loads unwarned.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local function boot(race)
    local c = ww.character()
    c.race = race
    local H = headless.new({ character = c, pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    return H
end

describe("a priority without a precombat list", function()
    it("recommends out of combat and in combat without raising", function()
        local H = boot()
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

describe("a priority naming another race's racial", function()
    it("a Human skips a blood_fury line as unknown, without raising", function()
        local H = boot("Human")
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            default = {
                { enabled = true, action = "blood_fury" },
                { enabled = true, action = "berserker_stance", criteria = "!action.blood_fury.known" },
            },
        }
        H.Hekili:LoadScripts()
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        H.Fire("PLAYER_REGEN_DISABLED")
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        assert.is_false(H.Hekili.Class.abilities.blood_fury.known)
        assert.are.equal("berserker_stance", out.recs[1] and out.recs[1].actionName)
    end)
end)

describe("a priority reading time to die", function()
    it("loads unwarned and reads the fight as far from over", function()
        local H = boot()
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            default = {
                { enabled = true, action = "berserker_stance", criteria = "fight_remains>600&target.time_to_die>600" },
            },
        }
        H.Hekili:LoadScripts()
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        H.Fire("PLAYER_REGEN_DISABLED")
        for _ = 1, 5 do
            t = t + 0.6
            assert(headless.cycle(H, t))
        end
        assert.are.same({}, H.errors)
        assert.are.equal("berserker_stance", out.recs[1] and out.recs[1].actionName)
    end)
end)
