-- tests/Forever/creature_type_spec.lua: the target's creature type (`target.creature_type`, UnitCreatureType's ID as a
-- key) and an ability's `usable_on`, through the real engine; the harness world's mob carries the type to the client.
local headless = require("Game.harness.headless")
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")
local SECRET = require("Game.State.helpers.fake_api").SECRET

describe("the target's creature type", function()
    local H, t

    local function cycle(creature) -- the client's answer for the target from now on, then one refresh
        H.ctl.creature.target = creature
        t = t + 0.2
        H.ctl.now = t
        assert(headless.cycle(H, t))
        return H.Hekili.State
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now
    end)

    after_each(function()
        H.Hekili.Class.abilities.hamstring.usable_on = nil
        H.Hekili.Class.abilities.hamstring.funcs.usable_on = nil
    end)

    it("reads the client's type ID as a key: undead, demon, unknown when secret or unlisted", function()
        local st = cycle("undead")
        assert.are.same({ "undead", true, false }, { st.target.creature_type, st.target.is_undead, st.target.is_demon })
        st = cycle("demon")
        assert.are.same({ "demon", false, true }, { st.target.creature_type, st.target.is_undead, st.target.is_demon })
        assert.are.equal("not_specified", cycle("not_specified").target.creature_type)
        assert.are.equal("unknown", cycle("unknown").target.creature_type) -- no ID: no target, or one unlisted
        assert.are.equal("unknown", cycle(SECRET).target.creature_type)
        assert.are.same({}, H.errors)
    end)

    it("usable_on: usable on a listed type or an unknown one, not on another; no field, usable on any", function()
        local hamstring = H.Hekili.Class.abilities.hamstring
        assert.is_true(cycle("beast"):IsUsable("hamstring"))
        hamstring.usable_on = { "undead", "demon" }
        assert.is_true(cycle("undead"):IsUsable("hamstring"))
        assert.is_true(cycle("demon"):IsUsable("hamstring"))
        local ok, why = cycle("beast"):IsUsable("hamstring")
        assert.are.same({ false, "target's creature type not in usable_on" }, { ok, why })
        assert.is_true(cycle("unknown"):IsUsable("hamstring")) -- never blocked on the unknown
        assert.are.same({}, H.errors)
    end)

    it("usable_on as a function: its list applies, its nil means any target", function()
        local list
        H.Hekili.Class.abilities.hamstring.funcs.usable_on = function()
            return list
        end
        list = { "undead" }
        assert.is_false((cycle("beast"):IsUsable("hamstring")))
        assert.is_true(cycle("undead"):IsUsable("hamstring"))
        list = nil
        assert.is_true(cycle("beast"):IsUsable("hamstring"))
        assert.are.same({}, H.errors)
    end)
end)

describe("the harness world's creature type", function()
    it("reaches the client: a content WORLD's creatureType is the mob's and the state's", function()
        local C = setmetatable({ WORLD = setmetatable({ creatureType = "undead" }, { __index = ww.WORLD }) }, {
            __index = ww,
        })
        local L = loop.new(C)
        local seen
        local run = loop.run(L, 1, {
            duration = 2,
            on = function()
                seen = L.us.Hekili.State.target.creature_type
            end,
        }, { { H = L.us } })
        assert.are.equal("undead", run.us.target.creatureType)
        assert.are.equal("undead", seen)
    end)
end)
