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

    -- Bloodrage stands in for any timed buff (10 s); the client's plain ready flag keeps its cooldown out of the way.
    local function buff(on) -- Bloodrage's aura on the player from now (its 10 s from the cast), or gone
        local id = H.Hekili.Class.auras.bloodrage.id
        H.ctl.auras.player.HELPFUL[1] = on and { spellId = id, expirationTime = on + 10, applications = 1 } or nil
        H.Fire("UNIT_AURA", "player")
    end
    local function to(at) -- the clock to `at`, then one refresh
        t = at - 0.2
        H.ctl.cooldown[H.Hekili.Class.abilities.bloodrage.id] = nil -- ready: the client's flag
        return cycle()
    end

    it("an aura that ran out is offered again: a 10 s buff not at 5 s, again at 11 s", function()
        lists({ { enabled = true, action = "bloodrage", use_off_gcd = 1, prepull_at = 10 } })
        assert.are.equal("bloodrage", cycle())
        cast("bloodrage")
        local t0 = t
        buff(t0)
        assert.are_not.equal("bloodrage", to(t0 + 5))
        to(t0 + 10)
        buff(false)
        assert.are.equal("bloodrage", to(t0 + 11))
        assert.are.same({}, H.errors)
    end)

    it("an aura replaced before it ran out stays done for the episode: replaced at 2 s, done through 60 s", function()
        lists({
            { enabled = true, action = "bloodrage", use_off_gcd = 1, prepull_at = 10 },
            { enabled = true, action = "defensive_stance", use_off_gcd = 1, prepull_at = 1.5 },
        })
        assert.are.equal("bloodrage", cycle())
        cast("bloodrage")
        local t0 = t
        buff(t0)
        assert.are.equal("defensive_stance", to(t0 + 1))
        t = t0 + 2 - 1.6
        cast("defensive_stance") -- at t0 + 2, and the stand-in's aura goes with it, as a seal replaces a seal
        buff(false)
        for at = t0 + 3, t0 + 60, 3 do
            assert.is_false(to(at), at - t0)
        end
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
