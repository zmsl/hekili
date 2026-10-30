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

    it("starts a queued strike's cooldown at the swing that takes it, and the client answers it then", function()
        setup()
        W.emit({ kind = "pull" })
        behaviours.melee({ rates = { miss = 0, dodge = 0, parry = 0, crit = 0 }, phase = { 1 } })(W, us)
        W.t = 0.2
        assert.is_true(W.press(us, "q", { spell = 7, cost = 0, offGcd = true, onNextSwing = true, cooldown = 6 }))
        assert.is_nil(us.cdUntil.q) -- queued, not yet on cooldown
        W.run(1.5) -- the swing at 1 takes it
        assert.are.equal(7, us.cdUntil.q)
        local observer = require("Game.harness.observer")
        local s = observer.observe(W, setmetatable({ plain = true }, { __index = observer.DEFAULTS }))
        local cds = {}
        for i = 1, s.n do
            if s.ev[i] == "@cooldown" and s.a1[i] == 7 then
                cds[#cds + 1] = { s.t[i], s.a3[i] }
            end
        end
        assert.are.same({ { 1, 6 }, { 7, 0 } }, cds)
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
                w.hit(e, e.target, 30, 1)
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

    it("runs wowsims's spirit multiplier and capped casting share while an fsr aura is up", function()
        setup()
        W.startRegen(
            us,
            {},
            0.1,
            nil,
            { [POOL] = { 10, 12, share = 0.5, auras = { [77] = { spirit = 16, share = 1 } } } }
        )
        assert.are.same({ 22, 12 }, { W.regenRate(us, POOL, "idle"), W.regenRate(us, POOL, "casting") })
        W.applyAura(us, 77, 10)
        assert.are.same({ 322, 322 }, { W.regenRate(us, POOL, "idle"), W.regenRate(us, POOL, "casting") })
    end)

    it("adds an fsr aura's mp5 in both windows and in the read", function()
        setup()
        W.startRegen(us, {}, 0.1, nil, { [POOL] = { 10, 2, auras = { [7801] = { mp5 = 5 } } } })
        W.applyAura(us, 7801, 10)
        assert.are.same({ 17, 7 }, { W.regenRate(us, POOL, "idle"), W.regenRate(us, POOL, "casting") })
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

    it("holds an `fsr` pool's casting rate to a paid channel's end, and to the 5 s rule after a clip", function()
        setup()
        W.startRegen(us, {}, 0.1, nil, { [POOL] = { 10, 2 } })
        local chan = { spell = 1, gcd = 1.5, cost = 10, pt = POOL, channel = { length = 8, tick = 1 } }
        assert.is_true(W.press(us, "chan", chan))
        W.run(6.5)
        assert.are.equal(2, W.regenRate(us, POOL)) -- held past the 5 s
        W.run(8.05)
        assert.are.equal(12, W.regenRate(us, POOL))
        assert.is_true(W.press(us, "chan", chan)) -- at 8.05, clipped at 14.05
        W.run(14.05)
        assert.are.equal(2, W.regenRate(us, POOL))
        W.stopChannel(us)
        assert.are.equal(12, W.regenRate(us, POOL)) -- 6 s after its spend: the 5 s rule
        W.run(20)
        W.press(us, "free", { spell = 2, gcd = 1.5, channel = { length = 8, tick = 1 } }) -- free: holds nothing
        W.run(26)
        assert.are.equal(12, W.regenRate(us, POOL))
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

    describe("parry haste (parry-haste spec decision 63, the owner's ruling 2026-10-23)", function()
        local function ms(t)
            return math.floor(t * 1000 + 0.5) / 1000
        end
        local function swingsOf(e, hand)
            local out = {}
            for _, ev in ipairs(W.truth) do
                if ev.kind == "swing" and ev.src == e and (hand == nil or ev.hand == hand) then
                    out[#out + 1] = ms(ev.t)
                end
            end
            return out
        end

        it("its rule is the belief's L.ParryPull on a grid", function()
            local L = require("Game.State.helpers.load").module().VirtualStateInternal.Log
            for _, d in ipairs({ 1.5, 2.0, 2.353, 3.6 }) do
                for k = 0, 80 do
                    local r = d * k / 80
                    assert.are.equal(L.ParryPull(r, d), behaviours.parryPull(r, d))
                end
            end
        end)

        it("pulls the mob's next swing when it parries ours, down to 20% of its swing left", function()
            setup()
            us.avoid = { miss = 0, dodge = 0, parry = 0 }
            behaviours.melee({ rates = { miss = 0, dodge = 0, parry = 1, crit = 0 }, phase = { 1 } })(W, us)
            behaviours.mob({ phase = 0.5 })(W, mob)
            W.run(3.5)
            -- the mob at 0.5; our parried swing at 1 (its 2.5 due, r 1.5): 0.8 -> 1.7; ours at 3 (its 3.7 due, r 0.7):
            -- 0.3 -> 3.4
            assert.are.same({ 0.5, 1.7, 3.4 }, swingsOf(mob))
            assert.are.same({ 1, 3 }, swingsOf(us)) -- the attacker's own timer untouched
        end)

        it("pulls our main hand when we parry, never the off hand; nothing with the world's knob off", function()
            setup()
            us.weapons[2] = { 10, 10, 2.0 }
            us.avoid = { miss = 0, dodge = 0, parry = 1 }
            mob.weapons[1][3] = 3
            behaviours.melee({ rates = { miss = 0, dodge = 0, parry = 0, crit = 0 }, phase = { 1, 1.1 } })(W, us)
            behaviours.mob({ phase = 0.2 })(W, mob)
            W.run(4.0)
            -- parried at 0.2 (our 1 due, r 0.8): 0.4 -> 0.6; at 3.2 (our 4.6 due, r 1.4): 0.8 -> 3.8
            assert.are.same({ 0.6, 2.6, 3.8 }, swingsOf(us, 1))
            assert.are.same({ 1.1, 3.1 }, swingsOf(us, 2))
            setup()
            W.parryHaste = false
            us.avoid = { miss = 0, dodge = 0, parry = 1 }
            mob.weapons[1][3] = 3
            behaviours.melee({ rates = { miss = 0, dodge = 0, parry = 0, crit = 0 }, phase = { 1 } })(W, us)
            behaviours.mob({ phase = 0.2 })(W, mob)
            W.run(4.0)
            assert.are.same({ 1, 3 }, swingsOf(us, 1))
        end)

        it("never has us parry with scenarios' canParry off (wowsims's CanParry); we do by default", function()
            local scenarios = require("Game.harness.scenarios")
            for _, can in ipairs({ true, false }) do
                local Wx = scenarios.build({ canParry = can, duration = 120, mobPeriod = 0.5 }, 1)
                local parried = 0
                for _, ev in ipairs(Wx.truth) do
                    if ev.kind == "swing" and ev.dst == Wx.ents[1] and ev.act == "PARRY" then
                        parried = parried + 1
                    end
                end
                assert.are.equal(can, parried > 0, tostring(can))
            end
        end)

        it(
            "rolls our instant hits on scenarios' mobAvoid and crit; the defaults are entities' and world.CRIT",
            function()
                local scenarios = require("Game.harness.scenarios")
                local function tally(o)
                    local Wx = scenarios.world(o, 1)
                    local n = { WOUND = 0, MISS = 0, DODGE = 0, PARRY = 0, crit = 0 }
                    for _ = 1, 4000 do
                        local act, flag = Wx.rollOutcome(Wx.ents[2])
                        n[act] = n[act] + 1
                        n.crit = n.crit + (flag == "CRITICAL" and 1 or 0)
                    end
                    return n
                end
                local d = tally({})
                assert.is_true(d.PARRY > 100 and math.abs(d.crit / 4000 - world.CRIT) < 0.02, tostring(d.crit))
                local n = tally({ mobAvoid = { miss = 0.02, dodge = 0.03, parry = 0, block = 0 }, crit = 0.3 })
                assert.are.equal(0, n.PARRY)
                assert.is_true(math.abs(n.MISS / 4000 - 0.02) < 0.01 and math.abs(n.DODGE / 4000 - 0.03) < 0.01)
                assert.is_true(math.abs(n.crit / 4000 - 0.3) < 0.03, tostring(n.crit))
            end
        )
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
        W.run(1.5) -- the swing at 1 (its rage at the swing), in form 0: nothing
        assert.are.equal(0, us.power)
        W.setForm(us, 1)
        W.run(3.5) -- the swing at 3: 5 and the crit's 3
        assert.are.equal(8, us.power)
    end)

    for _, swing in ipairs({ false, true }) do
        local how = swing and "with swingType 2" or "from its cast successes alone (the modelled clock)"
        it("shoots a ranged hand every ranged speed, and the belief's ranged clock follows " .. how, function()
            local observer, drive = require("Game.harness.observer"), require("Game.harness.drive")
            local fs = require("Game.State.helpers.fake_spec")
            setup({ ranged = { 20, 30, 2.8 } })
            W.t = 0.5
            W.emit({ kind = "prepull" })
            W.t = 1
            W.emit({ kind = "pull" })
            W.startRanged(us, fs.SPENDER_R, { swing = swing, delay = 0.2 })
            W.at(10, function()
                us.rangedOn = false
            end)
            W.run(15)
            local shots, swings = {}, 0
            for _, ev in ipairs(W.truth) do
                if ev.kind == "cast" then
                    shots[#shots + 1] = ev.t
                elseif ev.kind == "swing" and ev.hand == 3 then
                    swings = swings + 1
                end
            end
            assert.are.equal(4, #shots) -- 1.2, 4.0, 6.8, 9.6
            assert.is_true(math.abs(shots[4] - 9.6) < 1e-9)
            assert.are.equal(swing and 4 or 0, swings)
            assert.is_true(mob.health < 1e6) -- the shots' outcomes
            local s = observer.observe(W)
            local seen = {}
            for i = 1, s.n do
                if s.ev[i] == "@rangedSpeed" or (s.ev[i] == "PLAYER_SWING" and s.a2[i] == 2) then
                    seen[#seen + 1] = s.ev[i] .. " " .. s.a1[i]
                end
            end
            local want = { "@rangedSpeed 2.8" }
            for k = 1, swings do
                want[k + 1] = "PLAYER_SWING 2.8"
            end
            assert.are.same(want, seen)
            local c = drive.boot({
                boot = function(c)
                    c.I.Build(fs.def(fs.new(9, nil, true)), 0.1)
                    c.VS.Start(c.api) -- fake_api's 3.1 until the cache read answers 2.8
                end,
            })
            drive.run(c, s)
            drive.restore(c)
            assert.are.equal(2.8, c.VS.SwingSpeed(3, 12).est)
            assert.is_true(math.abs(c.VS.LastSwing(3) - 9.6) < 1e-9)
            assert.is_true(math.abs(c.VS.Swing(3, 12).est - 12.4) < 1e-9)
        end)
    end
end)

describe("the world's position", function()
    it(
        "moves our character: no white swing out of reach, a press refused outside its range, the client told",
        function()
            local observer = require("Game.harness.observer")
            local W = world.new(5)
            local us = W.add(entities.new({ guid = "Player-1", weapons = { { 10, 10, 2.0 } } }))
            local mob =
                W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } }, health = 1e6 }))
            us.target, mob.target = mob, us
            assert.is_true(W.inMelee()) -- no positions: in reach
            W.at(0.2, function()
                W.moveTo(us, 25)
            end)
            W.at(0.5, function()
                W.emit({ kind = "prepull" })
            end)
            W.at(1, function()
                W.emit({ kind = "pull" })
                behaviours.melee({ phase = { 0.5 } })(W, us)
            end)
            W.at(6, function()
                W.moveTo(us, 5)
            end)
            local strike = { spell = 7, gcd = 1.5, range = { 0, 5 } }
            W.run(3)
            assert.are.same({ false, "range" }, { W.press(us, "s", strike) })
            W.run(8)
            assert.is_true(W.press(us, "s", strike))
            W.run(12)
            local swings = {}
            for _, ev in ipairs(W.truth) do
                if ev.kind == "swing" and ev.src == us then
                    swings[#swings + 1] = ev.t
                end
            end
            assert.are.same({ 7.5, 9.5, 11.5 }, swings) -- 1.5, 3.5 and 5.5 fell out of reach
            local s = observer.observe(W)
            local seen = {}
            for i = 1, s.n do
                if s.ev[i] == "@distance" then
                    seen[#seen + 1] = { s.t[i], s.a1[i], s.a2[i] }
                end
            end
            assert.are.same({ { 0.2, "target", 25 }, { 6, "target", 5 } }, seen)
        end
    )
end)

-- Central fix 27: what a kit's resources read beyond the power types: bag counts (a reagent), the pet unit and its
-- power, the character's stats. The world keeps the truth, the observer the client's answers (all plain on Forever:
-- C_Item.GetItemCount [W PR13], UnitExists("pet") [W PR14], UnitPower("pet") plain 0 with no pet [W PR12], UnitStat
-- read out of combat).
describe("the character's bags, pet and stats", function()
    local observer = require("Game.harness.observer")
    local drive = require("Game.harness.drive")
    local fake = require("Game.State.helpers.fake_api")
    local ITEM, PT = 6000, 0 -- an item ID and the pet's power type, as bare numbers

    local function setup()
        local W = world.new(5)
        local us = W.add(entities.new({
            guid = "Player-1",
            bags = { [ITEM] = 2 },
            pet = { pt = PT, max = 400, power = 100, regen = 10, tick = 2 },
            stats = { 20, 30, 40, 50, 60 },
        }))
        return W, us
    end

    it("spends a press's reagent when its cast lands, refuses a press short of it, and gains an item", function()
        local W, us = setup()
        W.t = 1
        assert.is_true(W.press(us, "a", { spell = 1, gcd = 0, reagent = { ITEM, 1 } }))
        assert.are.equal(1, W.items(us, ITEM))
        assert.is_true(W.press(us, "b", { spell = 2, gcd = 0, cast = 1, reagent = { ITEM, 1 } }))
        assert.are.equal(1, W.items(us, ITEM)) -- a hard cast pays at its end
        W.run(2.5)
        assert.are.equal(0, W.items(us, ITEM))
        assert.are.same({ false, "reagent" }, { W.press(us, "a", { spell = 1, gcd = 0, reagent = { ITEM, 1 } }) })
        assert.is_true(W.press(us, "c", { spell = 3, gcd = 0, item = { ITEM, 3 } }))
        assert.are.same({ 3, 0 }, { W.items(us, ITEM), W.items(us, ITEM + 1) })
    end)

    it(
        "regenerates the pet's power on its ticks while it is up; a summon brings a full pet, a dismissal none",
        function()
            local W, us = setup()
            W.startPetRegen(us)
            W.run(4.5) -- ticks at 2 and 4
            assert.are.equal(140, us.pet.power)
            W.petGain(us, -100) -- a spend
            assert.are.equal(40, us.pet.power)
            assert.is_true(W.press(us, "d", { spell = 4, gcd = 0, pet = "dismiss" }))
            W.run(8.5)
            assert.are.same({ false, 40 }, { us.pet.up, us.pet.power }) -- no regen while down
            assert.is_true(W.press(us, "s", { spell = 5, gcd = 0, pet = "summon" }))
            assert.are.same({ true, 400 }, { us.pet.up, us.pet.power })
        end
    )

    it("answers the bag counts, the pet unit and its power and the stats as the client does", function()
        local W, us = setup()
        W.startPetRegen(us)
        W.at(1, function()
            W.press(us, "a", { spell = 1, gcd = 0, reagent = { ITEM, 1 } })
        end)
        W.at(3, function()
            W.dismissPet(us)
        end)
        W.at(5, function()
            W.summonPet(us)
        end)
        W.run(6)
        local s = observer.observe(W, observer.DEFAULTS)
        local got, stats = {}, nil
        for i = 1, s.n do
            local ev = s.ev[i]
            if ev == "@itemCount" or ev == "@pet" or ev == "@petPower" or ev == "UNIT_PET" then
                got[#got + 1] = { s.t[i], ev, s.a1[i], s.a2[i], s.a3[i] }
            elseif ev == "@stats" then
                stats = { s.t[i], s.a1[i] }
            end
        end
        assert.are.same({
            { 0, "@itemCount", ITEM, 2 },
            { 0, "@pet", true, PT, 100 }, -- the client's state at login (no event)
            { 1, "@itemCount", ITEM, 1 },
            { 2, "@petPower", 120 },
            { 3, "@pet", false, PT, 120 },
            { 3, "UNIT_PET", "player" },
            { 5, "@pet", true, PT, 400 },
            { 5, "UNIT_PET", "player" },
        }, got)
        assert.are.same({ 0, us.stats }, stats)
        -- Fix 31 G2: the pet's power is never ours, on a plain client too (our pool never moves after login here)
        local plain = setmetatable({ plain = true }, { __index = observer.DEFAULTS })
        local p = observer.observe(W, plain)
        for i = 1, p.n do
            assert.is_false(p.t[i] > 0 and (p.ev[i] == "@power" or p.ev[i] == "@truth"), p.ev[i] .. " at " .. p.t[i])
        end
        local api, ctl = fake.new()
        local c = {}
        for i = 1, s.n do
            if s.ev[i]:byte(1) == 64 then
                ctl.now = s.t[i]
                drive.op(c, ctl, s.ev[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
            end
        end
        assert.are.same({ 1, true, 400, 400, 0, 60 }, {
            api.C_Item.GetItemCount(ITEM),
            api.UnitExists("pet"),
            api.UnitPower("pet"),
            api.UnitPower("pet", PT),
            api.UnitPower("pet", 3), -- not the pet's power type
            (api.UnitStat("player", 5)),
        })
    end)
end)
