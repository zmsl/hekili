-- tests/Forever/prepull_spec.lua: a precombat entry with `prepull_at` (Engine/Sim/Core.lua's prepull schedule) is
-- recommended once an out-of-combat episode, through the real engine. Three exclusive stances stand in for any
-- mutually exclusive buffs (two seals): casting one removes the others, the loop a plain `!buff.X.up` guard cannot stop.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("a prepull schedule (prepull_at)", function()
    local H, t, out

    local function cycle()
        t = t + 0.2
        H.ctl.now = t
        assert(headless.cycle(H, t))
        return out.count > 0 and out.recs[1].actionName or false
    end

    local function cast(key) -- our cast, its stance the client's form from then
        t = t + 1.6 -- past the stances' shared cooldown
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. key, H.Hekili.Class.abilities[key].id)
        H.ctl.form = ww.FORM[key]
        H.Fire("UPDATE_SHAPESHIFT_FORM")
    end

    local function lists(precombat)
        H.Hekili.DB.profile.packs[ww.PACK].lists = { precombat = precombat, default = {} }
        H.Hekili:LoadScripts()
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

    it("recommends A once, then B once after A's cast, then nothing", function()
        lists({
            { enabled = true, action = "defensive_stance", use_off_gcd = 1, prepull_at = 10 },
            { enabled = true, action = "berserker_stance", use_off_gcd = 1, prepull_at = 1.5 },
        })
        assert.are.equal("defensive_stance", cycle())
        cast("defensive_stance")
        assert.are.equal("berserker_stance", cycle())
        cast("berserker_stance")
        assert.is_false(cycle()) -- Defensive Stance is down again, but it was cast this episode
        assert.are.same({}, H.errors)
    end)

    it("an entry whose aura is seen up is done for the episode, even after it falls off", function()
        lists({
            { enabled = true, action = "battle_stance", use_off_gcd = 1, prepull_at = 10 },
            { enabled = true, action = "defensive_stance", use_off_gcd = 1, prepull_at = 1.5 },
        })
        assert.are.equal("defensive_stance", cycle()) -- Battle Stance is up: done
        cast("defensive_stance")
        assert.is_false(cycle()) -- Battle Stance fell off: still done, no loop
        assert.are.same({}, H.errors)
    end)

    it("entering and leaving combat starts a new episode", function()
        lists({
            { enabled = true, action = "battle_stance", use_off_gcd = 1, prepull_at = 10 },
            { enabled = true, action = "defensive_stance", use_off_gcd = 1, prepull_at = 1.5 },
        })
        cycle()
        cast("defensive_stance")
        assert.is_false(cycle())
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_false(cycle()) -- in combat: the precombat list is filtered
        t = t + 10
        H.ctl.now = t
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("battle_stance", cycle()) -- a new episode, in Defensive Stance
        assert.are.same({}, H.errors)
    end)

    it("an entry without prepull_at keeps the plain list's behaviour: recommended while its condition holds", function()
        lists({
            { enabled = true, action = "defensive_stance", use_off_gcd = 1 },
            { enabled = true, action = "berserker_stance", use_off_gcd = 1 },
        })
        assert.are.equal("defensive_stance", cycle())
        cast("defensive_stance")
        assert.are.equal("berserker_stance", cycle())
        cast("berserker_stance")
        assert.are.equal("defensive_stance", cycle()) -- the loop prepull_at stops
        assert.are.same({}, H.errors)
    end)
end)
