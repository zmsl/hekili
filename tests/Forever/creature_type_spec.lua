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

    -- L1142: under the Map restriction (the target's GUID secret) no plain type read is trusted, so none is made: a
    -- plain answer there reads unknown too, and the client is not asked.
    it("restricted (the target's GUID secret): unknown, not Undead or Demon, the client not asked", function()
        H.ctl.guid.target = SECRET
        local calls = H.ctl.creatureCalls
        local st = cycle("undead")
        assert.are.same(
            { "unknown", false, false },
            { st.target.creature_type, st.target.is_undead, st.target.is_demon }
        )
        assert.are.equal(calls, H.ctl.creatureCalls)
        collectgarbage("collect")
        collectgarbage("stop")
        local b = collectgarbage("count")
        for _ = 1, 50 do
            local _ = st.target.creature_type, st.target.is_undead, st.target.is_demon
        end
        local d = (collectgarbage("count") - b) * 1024
        collectgarbage("restart")
        assert.are.equal(0, d)
        H.ctl.guid.target = "Creature-1"
        assert.are.equal("undead", st.target.creature_type)
        assert.is_true(H.ctl.creatureCalls > calls)
        assert.are.same({}, H.errors)
    end)

    it(
        "usable_on: usable on a listed type, not on another; unknown, a plain range answer confirms; no field, any",
        function()
            local hamstring = H.Hekili.Class.abilities.hamstring
            assert.is_true(cycle("beast"):IsUsable("hamstring"))
            hamstring.usable_on = { "undead", "demon" }
            assert.is_true(cycle("undead"):IsUsable("hamstring"))
            assert.is_true(cycle("demon"):IsUsable("hamstring"))
            local ok, why = cycle("beast"):IsUsable("hamstring")
            assert.are.same({ false, "target's creature type not in usable_on" }, { ok, why })
            assert.is_true(cycle("unknown"):IsUsable("hamstring")) -- the range answer (true) confirms it
            assert.are.same({}, H.errors)
        end
    )

    -- L1141/L1142 (owner: be conservative): an ability with usable_on needs an attackable target and a confirmed type.
    -- A plain type decides; under the Map restriction (a dungeon or raid: the target's GUID and type read secret, L237)
    -- no type read is trusted and the client's range answer decides: plain true or false is a type the spell can hit, a
    -- plain nil one it cannot (L238), a secret answer is unconfirmed. The pack's Exorcism case, on a generic ability.
    describe("usable_on's confirmation", function()
        local hamstring, id
        local NIL = { false, "creature type unknown; range nil: wrong target type" }
        local SECRET_RANGE = { false, "creature type unknown; range secret: unconfirmed" }
        local NO_TARGET = { false, "usable_on: no attackable target" }
        local MISS = { false, "target's creature type not in usable_on" }

        before_each(function()
            hamstring = H.Hekili.Class.abilities.hamstring
            id = H.ns.VirtualState.KnownID(hamstring.id) -- the rank the facade asks the client by
            hamstring.usable_on = { "undead", "demon" }
            H.ctl.distance.target = 3
        end)

        after_each(function()
            H.ctl.exists.target, H.ctl.friendly.target, H.ctl.guid.target = true, nil, "Creature-1"
            H.ctl.distance.target, H.ctl.ranges[id], H.ctl.dead.target = nil, nil, nil
        end)

        local function range(answer) -- the client's IsSpellInRange for the ability at 3 yd
            if answer == SECRET then
                H.ctl.ranges[id], H.ctl.distance.target = nil, SECRET
            elseif answer == nil then
                H.ctl.ranges[id], H.ctl.distance.target = { 0, 0 }, 3 -- maxRange 0: the client's plain nil
            else
                H.ctl.ranges[id], H.ctl.distance.target = answer and { 0, 5 } or { 0, 2 }, 3
            end
        end

        local function restricted(on) -- the Map restriction (addonMapRestrictionsForced=1): the target's GUID secret
            H.ctl.guid.target = on and SECRET or "Creature-1"
        end

        it("no target, or one not attackable: refused whatever the type and range answer", function()
            range(true)
            H.ctl.combat = true -- in combat (the owner's report: shown with no target mid-fight)
            H.Fire("PLAYER_REGEN_DISABLED")
            H.ctl.exists.target = false
            local st = cycle("unknown")
            assert.is_true(st.combat > 0)
            assert.are.same(NO_TARGET, { st:IsUsable("hamstring") }) -- the live client's no target
            assert.are.same(NO_TARGET, { cycle("undead"):IsUsable("hamstring") })
            H.ctl.exists.target = SECRET
            assert.are.same(NO_TARGET, { cycle("undead"):IsUsable("hamstring") })
            H.ctl.exists.target, H.ctl.friendly.target = true, true
            assert.are.same(NO_TARGET, { cycle("undead"):IsUsable("hamstring") })
            H.ctl.friendly.target = SECRET -- open world: a secret answer refuses
            assert.are.same(NO_TARGET, { cycle(SECRET):IsUsable("hamstring") })
            H.ctl.friendly.target, H.ctl.dead.target = nil, true -- a dead target
            assert.are.same(NO_TARGET, { cycle("undead"):IsUsable("hamstring") })
            restricted(true)
            assert.are.same(NO_TARGET, { cycle(SECRET):IsUsable("hamstring") })
            H.ctl.dead.target = SECRET -- unknown: the type or range answer decides
            assert.is_true(cycle(SECRET):IsUsable("hamstring"))
            restricted(false)
            assert.is_true(cycle("undead"):IsUsable("hamstring"))
            assert.are.same({}, H.errors)
        end)

        -- L1161: in a restricted area UnitCanAttack's secrecy is unknown (L515); a secret answer does not refuse there,
        -- the range answer alone decides (a plain nil also answers a target the spell cannot be cast at).
        it("restricted, UnitCanAttack secret: the range answer decides; a plain false still refuses", function()
            restricted(true)
            H.ctl.friendly.target = SECRET
            range(true)
            assert.is_true(cycle(SECRET):IsUsable("hamstring"))
            range(false)
            assert.is_true(cycle(SECRET):IsUsable("hamstring"))
            range(nil)
            assert.are.same(NIL, { cycle(SECRET):IsUsable("hamstring") })
            range(SECRET)
            assert.are.same(SECRET_RANGE, { cycle(SECRET):IsUsable("hamstring") })
            H.ctl.friendly.target = true
            range(true)
            assert.are.same(NO_TARGET, { cycle(SECRET):IsUsable("hamstring") })
            H.ctl.exists.target = SECRET
            H.ctl.friendly.target = SECRET
            assert.are.same(NO_TARGET, { cycle(SECRET):IsUsable("hamstring") })
            assert.are.same({}, H.errors)
        end)

        -- L1160: usable_on { "any" }: any attackable target, no type check; restricted, the range answer still decides.
        it('"any": an attackable living target of any type; restricted, the range answer decides', function()
            hamstring.usable_on = { "any" }
            range(nil)
            assert.is_true(cycle("humanoid"):IsUsable("hamstring"))
            assert.is_true(cycle("unknown"):IsUsable("hamstring"))
            H.ctl.exists.target = false
            assert.are.same(NO_TARGET, { cycle("unknown"):IsUsable("hamstring") })
            H.ctl.exists.target, H.ctl.friendly.target = true, true
            assert.are.same(NO_TARGET, { cycle("humanoid"):IsUsable("hamstring") })
            H.ctl.friendly.target, H.ctl.dead.target = nil, true
            assert.are.same(NO_TARGET, { cycle("humanoid"):IsUsable("hamstring") })
            H.ctl.dead.target = nil
            restricted(true)
            range(true)
            assert.is_true(cycle(SECRET):IsUsable("hamstring"))
            range(nil) -- no type to be wrong: the client cannot cast it at this target
            assert.are.same({ false, "range nil: not a valid target" }, { cycle(SECRET):IsUsable("hamstring") })
            range(SECRET)
            assert.are.same(SECRET_RANGE, { cycle(SECRET):IsUsable("hamstring") })
            assert.are.same({}, H.errors)
        end)

        -- Review M8: one pass can span a target change (the update yields across frames); the type is the client's
        -- answer at the check, not the one read earlier in the pass.
        it("a target change mid-pass: the new target's type decides", function()
            range(true)
            local st = cycle("undead")
            assert.is_true(st:IsUsable("hamstring"))
            assert.is_true(st.target.is_undead)
            H.ctl.creature.target = "humanoid" -- no refresh: the same pass
            assert.are.same(MISS, { st:IsUsable("hamstring") })
            assert.are.same({ "humanoid", false }, { st.target.creature_type, st.target.is_undead })
            assert.are.same({}, H.errors)
        end)

        it("open world: a plain type decides, whatever the range answer", function()
            range(nil)
            assert.is_true(cycle("undead"):IsUsable("hamstring"))
            assert.is_true(cycle("demon"):IsUsable("hamstring"))
            range(true)
            assert.are.same(MISS, { cycle("humanoid"):IsUsable("hamstring") })
            assert.are.same({}, H.errors)
        end)

        it("the target-swap poll (type plainly unknown): the range answer decides", function()
            range(true)
            assert.is_true(cycle("unknown"):IsUsable("hamstring"))
            range(false)
            assert.is_true(cycle("unknown"):IsUsable("hamstring"))
            range(nil)
            assert.are.same(NIL, { cycle("unknown"):IsUsable("hamstring") })
            range(SECRET)
            assert.are.same(SECRET_RANGE, { cycle("unknown"):IsUsable("hamstring") })
            range(true) -- a readable GUID, the type secret: the range answer decides too
            assert.is_true(cycle(SECRET):IsUsable("hamstring"))
            range(nil)
            assert.are.same(NIL, { cycle(SECRET):IsUsable("hamstring") })
            assert.are.same({}, H.errors)
        end)

        it("restricted, type secret: plain true or false confirms, plain nil or secret refuses", function()
            restricted(true)
            range(true)
            assert.is_true(cycle(SECRET):IsUsable("hamstring"))
            range(false) -- out of range: usable here; the range filter alone refuses it
            local st = cycle(SECRET)
            assert.is_true(st:IsUsable("hamstring"))
            st.rangefilter = true
            assert.are.same({ false, "filtered out of range" }, { st:IsUsable("hamstring") })
            st.rangefilter = false
            range(nil)
            assert.are.same(NIL, { cycle(SECRET):IsUsable("hamstring") })
            range(SECRET)
            assert.are.same(SECRET_RANGE, { cycle(SECRET):IsUsable("hamstring") })
            assert.are.same({}, H.errors)
        end)

        it("restricted: a plain type read is never trusted, the range answer decides", function()
            restricted(true)
            range(nil)
            assert.are.same(NIL, { cycle("undead"):IsUsable("hamstring") })
            range(SECRET)
            assert.are.same(SECRET_RANGE, { cycle("demon"):IsUsable("hamstring") })
            range(true)
            assert.is_true(cycle("humanoid"):IsUsable("hamstring"))
            assert.are.same({}, H.errors)
        end)

        it("no usable_on: none of it applies", function()
            hamstring.usable_on = nil
            restricted(true)
            range(nil)
            assert.is_true(cycle(SECRET):IsUsable("hamstring"))
            H.ctl.exists.target = false
            assert.is_true(cycle("unknown"):IsUsable("hamstring"))
            assert.are.same({}, H.errors)
        end)

        it("allocates nothing on any branch", function()
            local cases = {
                { "undead", true, false },
                { "humanoid", true, false },
                { "unknown", true, false },
                { "unknown", nil, false },
                { "unknown", SECRET, false },
                { SECRET, true, true },
                { SECRET, nil, true },
                { SECRET, SECRET, true },
                { "undead", nil, true },
                { "humanoid", nil, false, { "any" } },
                { SECRET, true, true, { "any" } },
                { SECRET, nil, true, { "any" } },
            }
            for i, c in ipairs(cases) do
                hamstring.usable_on = c[4] or hamstring.usable_on
                restricted(c[3])
                range(c[2])
                local st = cycle(c[1])
                st:IsUsable("hamstring")
                collectgarbage("collect")
                collectgarbage("stop")
                local b = collectgarbage("count")
                for _ = 1, 50 do
                    st:IsUsable("hamstring")
                end
                local d = (collectgarbage("count") - b) * 1024
                collectgarbage("restart")
                assert.are.equal(0, d, "case " .. i)
            end
            H.ctl.exists.target = false
            local st = cycle("unknown")
            st:IsUsable("hamstring")
            collectgarbage("collect")
            collectgarbage("stop")
            local b = collectgarbage("count")
            st:IsUsable("hamstring")
            local d = (collectgarbage("count") - b) * 1024
            collectgarbage("restart")
            assert.are.equal(0, d, "no target")
        end)
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
