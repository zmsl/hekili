-- tests/Game/harness/world_spec.lua (GCD kinds design §2.1-§2.2): the world's truth for several resources, regen
-- and out-of-combat decay, the GCD's refusal, form shifts with their resource rules, and white rage by form and crit.
-- Class-neutral: power types and aura IDs are bare numbers.
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local behaviours = require("Game.harness.behaviours")

describe("the world's resources", function()
    local W, us, mob
    local SWUNG, POOL, POINTS = 1, 3, 4 -- the swing-paid type, a regenerating pool, a points resource

    local function setup(o)
        W = world.new(3)
        us = W.add(entities.new({
            guid = "Player-1",
            weapons = { { 10, 10, 2.0 } },
            res = { [POOL] = { cur = 50, max = 100 }, [POINTS] = { cur = 0, max = 5 } },
            formSpeed = { [1] = 2.5, [2] = 1.0 },
        }))
        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } }, health = 1e6 }))
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        us.target, mob.target = mob, us
        for key, v in pairs(o or {}) do
            us[key] = v
        end
    end

    it("refuses a press until the GCD and its latency are over, and keeps each type's cost apart", function()
        setup({ gcdLatency = 0.05 })
        W.t = 10
        assert.is_true(W.press(us, "a", { spell = 1, gcd = 1.0, cost = 20, pt = POOL }))
        assert.are.same({ 30, 0, 11.05 }, { W.res(us, POOL), us.power, us.gcdUntil })
        W.t = 11.04
        assert.are.same({ false, "gcd" }, { W.press(us, "b", { spell = 2, gcd = 1.0 }) })
        assert.are.same({ false, "cost" }, { W.press(us, "c", { spell = 3, gcd = 0, cost = 40, pt = POOL }) })
        W.t = 11.05
        assert.is_true(W.press(us, "b", { spell = 2, gcd = 1.0 }))
        local casts = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" then
                casts[#casts + 1] = { ev.t, ev.gcd, ev.order }
            end
        end
        assert.are.same({ { 10, 1.05, 1 }, { 11.05, 1.05, 1 } }, casts)
    end)

    it("rolls the GCD flag's order from its own generator when mixed, leaving the world's two alone", function()
        setup({ gcdOrder = "mixed" })
        local before = { W.rng.next(), W.crng.next() }
        setup({ gcdOrder = "mixed" })
        local seen = {}
        for k = 1, 40 do
            W.t = 2 * k
            W.press(us, "a", { spell = 1, gcd = 1.0 })
            seen[W.truth[#W.truth].order] = true
        end
        assert.are.same({ true, true }, seen)
        assert.are.same(before, { W.rng.next(), W.crng.next() })
    end)

    it(
        "runs a builder's point on a landed hit, a finisher's spend of all, a drain, a gain and a ticking aura",
        function()
            setup()
            W.t = 1
            local hit = function(w, e)
                w.hit(e, e.target, 30)
            end
            W.press(us, "build", { spell = 1, gcd = 0, effect = hit, points = { POINTS, 1 } })
            W.press(us, "build", { spell = 1, gcd = 0, effect = hit, points = { POINTS, 1 } })
            assert.are.equal(2, W.res(us, POINTS))
            W.press(
                us,
                "finish",
                { spell = 2, gcd = 0, cost = 10, pt = POOL, points = { POINTS, "all" }, drain = POOL }
            )
            assert.are.same({ 0, 0 }, { W.res(us, POINTS), W.res(us, POOL) })
            W.press(us, "gain", { spell = 3, gcd = 0, gain = { POOL, 40 } })
            assert.are.equal(40, W.res(us, POOL))
            W.press(us, "tick", {
                spell = 4,
                gcd = 0,
                gain = { SWUNG, 10 },
                aura = { id = 77, duration = 10, tick = { pt = SWUNG, every = 1, amount = 2 } },
            })
            W.run(30)
            assert.are.equal(10 + 2 * 10, us.power) -- every tick lands, the one at its expiry too
            assert.is_nil(us.auras[77])
        end
    )

    it("regenerates at its rate every tick, capped, and by the ramp after its seconds in one form", function()
        setup()
        W.startRegen(us, { [POOL] = 10 }, 0.1, { s = 5, k = 1.25 })
        W.run(4.05)
        assert.is_true(math.abs(W.res(us, POOL) - 90) < 1e-6, tostring(W.res(us, POOL)))
        W.run(6)
        assert.are.equal(100, W.res(us, POOL)) -- capped: no event at the maximum
        W.press(us, "spend", { spell = 1, gcd = 0, cost = 100, pt = POOL })
        W.run(7.05) -- 6 s and more in form 0: the ramp's rate
        assert.is_true(math.abs(W.res(us, POOL) - 12.5) < 1e-6, tostring(W.res(us, POOL)))
        local last = W.truth[#W.truth]
        assert.are.same({ "regen", POOL }, { last.kind, last.pt })
    end)

    it("regenerates an `fsr` pool's spirit part only 5 s after our last cast's spend, the read naming both", function()
        setup()
        W.startRegen(us, {}, 0.1, nil, { [POOL] = { 10, 2 } }) -- spirit 10/s, mp5 2/s
        W.run(1.05)
        assert.is_true(math.abs(W.res(us, POOL) - 62) < 1e-6, tostring(W.res(us, POOL)))
        W.press(us, "spend", { spell = 1, gcd = 0, cost = 50, pt = POOL })
        W.run(6.05) -- the window to 6.0: 2/s through it
        assert.is_true(math.abs(W.res(us, POOL) - (12 + 2 * 5)) < 1e-6, tostring(W.res(us, POOL)))
        W.run(7.05)
        assert.is_true(math.abs(W.res(us, POOL) - (22 + 12)) < 1e-6, tostring(W.res(us, POOL)))
        assert.are.same(
            { 12, 2, 12 },
            { W.regenRate(us, POOL, "idle"), W.regenRate(us, POOL, "casting"), W.regenRate(us, POOL) }
        )
        local ev = W.emit({ kind = "stop" })
        assert.are.same({ 12, 2 }, { ev.regen[POOL], ev.regenCasting[POOL] })
    end)

    it("lets the victim's `taking` change a swing's rates and its `took` see the outcome", function()
        setup()
        local seen = {}
        us.taking = function(_, _, rates)
            rates.block = 1
        end
        us.took = function(_, attacker, act)
            seen[#seen + 1] = { attacker == mob, act }
        end
        behaviours.mob({ phase = 0.5 })(W, mob)
        W.run(3)
        assert.are.same({ { true, "BLOCK" }, { true, "BLOCK" } }, seen)
    end)

    it("lets our `landed` see each of our swings land, after its land event", function()
        setup()
        local seen = {}
        us.landed = function(w, act, hand)
            seen[#seen + 1] = { w.truth[#w.truth].kind, act ~= nil, hand }
        end
        behaviours.melee({
            land = function()
                return 0.4
            end,
            phase = { 0.1 },
        })(W, us)
        W.run(2.6)
        assert.are.same({ { "land", true, 1 }, { "land", true, 1 } }, seen)
    end)

    it(
        "decays out of combat stepped and front-loaded; an aura that pauses it moves the next quantum to its expiry",
        function()
            for _, paused in ipairs({ false, true }) do
                setup()
                us.power = 40
                W.t = 57
                W.applyAura(us, 88, 10)
                W.t = 60
                W.startDecay(us, { pt = SWUNG, rate = 1.25, interval = 1, pausedBy = paused and 88 })
                W.run(60.5)
                assert.are.equal(paused and 40 or 38.75, us.power)
                W.run(66.5)
                assert.are.equal(paused and 40 or 40 - 1.25 * 7, us.power)
                W.run(67.5)
                assert.are.equal(paused and 38.75 or 40 - 1.25 * 8, us.power, tostring(paused))
            end
        end
    )

    it(
        "shifts after its cast: the form, the main hand's period, the weapon factor and each type's entry rule",
        function()
            setup()
            us.power = 30
            W.t = 5
            local sh = {
                form = 1,
                dmgMult = 1.6,
                onEnter = {
                    [SWUNG] = "zero",
                    [POOL] = "keep",
                    [POINTS] = function(_, _, _, cur)
                        return cur + 2
                    end,
                },
            }
            assert.is_true(W.press(us, "shift", { spell = 9, gcd = 1.5, shift = sh }))
            assert.are.same(
                { 1, 2.5, 1.6, 0, 50, 2 },
                { us.form, us.weapons[1][3], us.dmgMult, us.power, W.res(us, POOL), W.res(us, POINTS) }
            )
            local kinds = {}
            for _, ev in ipairs(W.truth) do
                kinds[#kinds + 1] = ev.kind
            end
            assert.are.same({ "cast", "form", "gain", "gain" }, { kinds[1], kinds[2], kinds[3], kinds[4] })
            assert.is_table(W.truth[2].damage) -- out of combat: the caches read the form's own
            W.emit({ kind = "pull" })
            W.shift(us, { form = 2 })
            assert.are.same({ 1.0, nil }, { us.weapons[1][3], W.truth[#W.truth].damage }) -- in combat: no read
        end
    )

    it("pays white rage only in the paying form, and a crit's extra on top", function()
        setup()
        local rates = { miss = 0, dodge = 0, parry = 0, crit = 1 }
        behaviours.melee({
            rates = rates,
            land = function()
                return 0.1
            end,
            phase = { 1 },
            rage = { 5 },
            critRage = { 3 },
            payIn = 1,
        })(W, us)
        W.run(1.5) -- the swing at 1 lands at 1.1, in form 0: nothing
        assert.are.equal(0, us.power)
        W.setForm(us, 1)
        W.run(3.5) -- the swing at 3: 5 and the crit's 3
        assert.are.equal(8, us.power)
    end)
end)
