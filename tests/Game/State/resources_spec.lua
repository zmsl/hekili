-- tests/Game/State/resources_spec.lua: the resources family (spec §6.1). Golden scenario 2 (TDF
-- tests/model/belief_spec.lua:197, 568): the cost ladder bounds a resource, and regen is measured between two pins
-- net of our own spends.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

local ENERGY = 3

local function within(want, got, tol)
    assert.is_true(math.abs(want - got) <= (tol or 1e-6), ("want %s, got %s"):format(want, got))
end

describe("resources", function()
    local ns, VS, I, S, Obs

    local function boot(def)
        local api = fake.new()
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(def, 1)
        I.api = api
    end

    local function obs(kind, t, a, b, c)
        S.Direct(kind, t, a, b, c)
    end

    describe("a continuous resource (energy, 10/s declared)", function()
        local FINISHER, BUILDER = 1, 2

        before_each(function()
            boot({
                abilities = { { key = "finisher", spend = 25 }, { key = "builder", spend = 40 } },
                abilityIds = { { 1001 }, { 1002 } },
                abilitySlot = { 1, 1 },
                resources = { { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = true, regen = 10 } },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
        end)

        it("bounds a resource by the cost ladder: affordable finisher (25), unaffordable builder (40)", function()
            obs(Obs.Usable, 10, FINISHER, 1, 0)
            obs(Obs.Usable, 10, BUILDER, 0, 1)
            I.Fold(10, false)
            local e = VS.Power(ENERGY, 10)
            assert.are.equal(25, e.lo)
            within(40 - I.EPS, e.hi)
            within(40 - I.EPS, e.est) -- the estimate (100 at rest) snaps into the interval
            within(0.5 * (1 - (15 - I.EPS) / 100), e.conf) -- a snap halves the confidence for a while
            assert.are.equal("pinned", e.basis)
            within(25 + 10 * 0.9 * 2, VS.Power(ENERGY, 12).lo, 1e-6) -- then it moves with regen
        end)

        it("measures regen between two pins, net of our own spends", function()
            local function pinAt(t)
                obs(Obs.Usable, t, BUILDER, 0, 1)
                obs(Obs.Usable, t, BUILDER, 1, 0)
            end
            pinAt(10) -- 40 at 10
            I.Fold(10, false)
            I.ResourceShift(1, -40, 10, Obs.CastSuccess) -- our builder: 0 at 10
            pinAt(12) -- 40 again at 12: (40 - 40 + 40) / 2 = 20/s, exactly 2x the declared 10/s: accepted
            I.Fold(12, false)
            local rr = VS.Regen(ENERGY, 12)
            within(10 + I.ALPHA * 10, rr.est)
            assert.is_true(rr.lo < rr.est and rr.est < rr.hi)
            assert.are.equal("modelled", rr.basis)
        end)

        it("rests at its maximum of 100, as before rest became a flag", function()
            assert.are.same({ 100, 100 }, { VS.Power(ENERGY, 1).est, I.res.rest[1] })
        end)

        it("pins an exact plain read and widens a late one by the regen spread", function()
            obs(Obs.Read, 20, 1, 55, I.ReadOf.Resource)
            I.Fold(20, false)
            local e = VS.Power(ENERGY, 20)
            assert.are.same({ 55, 55, 55, "observed" }, { e.est, e.lo, e.hi, e.basis })
        end)
    end)

    describe("a ladder precondition (C9: a spender that also needs points)", function()
        local FINISHER, PLAIN, NOLADDER = 1, 2, 3

        before_each(function()
            boot({
                abilities = {
                    {
                        key = "finisher",
                        spend = 30,
                        funcs = {
                            usable = function()
                                return points.current > 0, "requires points" -- luacheck: ignore 113
                            end,
                        },
                    },
                    {
                        key = "reader",
                        spend = 20,
                        funcs = {
                            usable = function()
                                return target.missing.field -- luacheck: ignore 113 (a name the context lacks)
                            end,
                        },
                    },
                    { key = "noladder", spend = 50, ladder = false },
                },
                abilityIds = { { 1001 }, { 1002 }, { 1003 } },
                abilitySlot = { 1, 1, 1 },
                resources = {
                    { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = true, regen = 10 },
                    { key = "points", type = 4, token = "COMBO_POINTS", max = 5 },
                },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
        end)

        it("pins nothing from a finisher's short answer at 0 points, nor the flip once points come", function()
            obs(Obs.Usable, 10, FINISHER, 0, 1)
            I.Fold(10, false)
            assert.are.same( -- untouched: at rest, the modelled floor too
                { 100, 100, 100 },
                { VS.Power(ENERGY, 10).est, VS.Power(ENERGY, 10).lo, VS.Power(ENERGY, 10).hi }
            )
            I.ResourceShift(2, 1, 10.5, Obs.CastSuccess) -- a builder's point
            obs(Obs.Usable, 11, FINISHER, 1, 0) -- usable now: the points crossed, not the energy
            I.Fold(11, false)
            local e = VS.Power(ENERGY, 11)
            assert.are.same({ 100, 100 }, { e.est, e.lo }) -- a floor at the cost under the rest, no exact pin at 30
            assert.are.equal(30, I.res.lo0[1]) -- the measured floor
        end)

        it("pins the short answer once the precondition holds", function()
            I.ResourceShift(2, 2, 9, Obs.CastSuccess)
            obs(Obs.Usable, 10, FINISHER, 0, 1)
            I.Fold(10, false)
            within(30 - I.EPS, VS.Power(ENERGY, 10).est)
        end)

        it("keeps the ladder for a precondition that raises, and drops it for `ladder = false`", function()
            obs(Obs.Usable, 10, NOLADDER, 1, 0)
            obs(Obs.Usable, 10, NOLADDER, 0, 1)
            I.Fold(10, false)
            assert.are.same({ 100, 100 }, { VS.Power(ENERGY, 10).est, VS.Power(ENERGY, 10).lo }) -- no rung: at rest
            obs(Obs.Usable, 11, PLAIN, 0, 1)
            I.Fold(11, false)
            within(20 - I.EPS, VS.Power(ENERGY, 11).est)
        end)

        it("allocates nothing evaluating the precondition", function()
            local t = 10
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.01
                    obs(Obs.Usable, t, FINISHER, 0, 1)
                    obs(Obs.Usable, t, PLAIN, 0, 1)
                    I.Fold(t, false)
                end, 1000)
            )
        end)
    end)

    describe("the out-of-combat regen read", function()
        local RAGE = 1
        local api

        before_each(function()
            boot({
                abilities = {},
                abilityIds = {},
                abilitySlot = {},
                resources = {
                    { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = true, regen = 10 },
                    { key = "rage", type = RAGE, token = "RAGE", max = 100, regen = 2 },
                },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
            api = I.api
            VS.Start(api)
        end)

        local function poll(t)
            api.ctl.Tick(t)
            S.RunPolls(t)
            I.Fold(t, false)
        end

        it("skips a 0 for a resource resting at its maximum, and takes a positive read", function()
            api.ctl.regen[ENERGY] = { 0, 0 }
            poll(105)
            assert.are.equal(10, VS.Regen(ENERGY, 105).est)
            api.ctl.regen[ENERGY] = { 12, 12 }
            poll(110)
            assert.are.equal(12, VS.Regen(ENERGY, 110).est)
        end)

        it("takes a 0 for a resource resting at 0, as before", function()
            api.ctl.regen[RAGE] = { 0, 0 }
            poll(105)
            assert.are.equal(0, VS.Regen(RAGE, 105).est)
        end)
    end)

    describe("a swing-paid resource (rage, 9 a main-hand swing)", function()
        before_each(function()
            boot(fs.def(fs.new(9)))
        end)

        it("starts at its rest value with basis default, and moves only at swings", function()
            local r = VS.Power(fs.RAGE, 0)
            assert.are.same({ 0, "default" }, { r.est, r.basis })
            obs(Obs.Swing, 5, 1, 2.6, 1)
            I.Fold(5, false)
            r = VS.Power(fs.RAGE, 7)
            assert.are.same({ 9, "modelled" }, { r.est, r.basis })
            within(9 * (1 - I.REGEN_SPREAD), r.lo)
            assert.are.equal(100, r.hi) -- nothing bounded it from above yet
        end)

        it("never believes more than the maximum, however many swings land", function()
            for k = 1, 20 do
                obs(Obs.Swing, 5 + 2.6 * k, 1, 2.6, 1)
            end
            I.Fold(60, false)
            local r = VS.Power(fs.RAGE, 60)
            assert.are.same({ 100, 100 }, { r.est, r.hi })
            assert.is_true(r.lo <= 100)
        end)

        describe("a white crit (Swing c = 3 after the landed swing)", function()
            local function crits(crit)
                local def = fs.def(fs.new(9))
                def.resources[1].swingCrit = crit
                boot(def)
                I.res.scale[1] = 1.2
            end

            it("adds value x scale for a plain swing and value x scale + crit, unscaled, for a critical one", function()
                crits(7)
                obs(Obs.Swing, 5, 1, 2.6, 1)
                I.Fold(5, false)
                within(9 * 1.2, VS.Power(fs.RAGE, 5).est)
                obs(Obs.Swing, 7.6, 1, 2.6, 1)
                obs(Obs.Swing, 7.6, 1, 0, 3)
                I.Fold(7.6, false)
                local r = VS.Power(fs.RAGE, 7.6)
                within(2 * 9 * 1.2 + 7, r.est)
                within(2 * 9 * (1.2 - I.REGEN_SPREAD) + 7, r.lo)
            end)

            it("loses the bonus above the cap", function()
                crits(7)
                for k = 1, 9 do
                    obs(Obs.Swing, 2.6 * k, 1, 2.6, 1) -- 9 x 10.8 = 97.2
                end
                obs(Obs.Swing, 2.6 * 9, 1, 0, 3)
                I.Fold(30, false)
                assert.are.equal(100, VS.Power(fs.RAGE, 30).est)
            end)

            it("changes nothing for a swing entry without `crit`", function()
                crits(nil)
                obs(Obs.Swing, 5, 1, 2.6, 1)
                obs(Obs.Swing, 5, 1, 0, 3)
                I.Fold(5, false)
                within(9 * 1.2, VS.Power(fs.RAGE, 5).est)
            end)
        end)

        it("pays nothing for a swing that did not land (PLAYER_SWING, c = 4), and models the hit rate", function()
            obs(Obs.Swing, 5, 1, 2.6, 4)
            I.Fold(5, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 5).est)
            within(9 / 2.6 * 0.9, I.SwingPerSecond(1))
            for k = 1, 40 do -- three of four land
                obs(Obs.Swing, 5 + 2.6 * k, 1, 2.6, 4)
                if k % 4 ~= 0 then
                    obs(Obs.Swing, 5.4 + 2.6 * k, 1, 0, 1)
                end
            end
            I.Fold(120, false)
            within(9 / 2.6 * 0.75, I.SwingPerSecond(1), 9 / 2.6 * 0.1)
        end)

        it(
            "alternates pinned (the ladder) and modelled (a swing, a cast) and keeps lo at or above what was seen",
            function()
                obs(Obs.Usable, 5, 3, 1, 0) -- spender_c (10) usable
                obs(Obs.Usable, 5, 2, 0, 1) -- spender_b (15) short
                I.Fold(5, false)
                local r = VS.Power(fs.RAGE, 5)
                assert.are.equal("pinned", r.basis)
                assert.is_true(r.lo >= 10 and r.hi < 15)
                I.ResourceShift(1, -10, 6, Obs.CastSuccess)
                r = VS.Power(fs.RAGE, 6)
                assert.are.equal("modelled", r.basis)
                assert.is_true(r.hi - r.lo <= 15)
            end
        )

        describe("a swing and our cast at the same instant (spender_a, 10)", function()
            -- 9 before (one swing at 2.4), a swing at 5 and spender_a's success at 5: 9 + 9 - 10 = 8 either way round
            local function scenario(swingFirst)
                obs(Obs.Swing, 2.4, 1, 0, 1)
                I.Fold(2.4, false)
                if swingFirst then
                    obs(Obs.Swing, 5, 1, 0, 1)
                end
                obs(Obs.CastSuccess, 5, 1) -- the rung (at least 10 at 5), then Families/Now.lua's pay
                I.Fold(5, false)
                if not swingFirst then
                    I.Settle(5.47) -- the clock moves on: the credit below folds late (lag 0.47)
                    obs(Obs.Swing, 5, 1, 0, 1) -- its wound came 0.47 s after the success: back-dated to the swing
                    I.Fold(5.47, false)
                end
                return VS.Power(fs.RAGE, 6)
            end

            it("ends at the rage of the swing credited before the spend, in both delivery orders", function()
                local a = scenario(true)
                boot(fs.def(fs.new(9)))
                local b = scenario(false)
                within(8, a.est)
                within(a.est, b.est)
                within(a.lo, b.lo) -- (hi differs only by the cap: 100 + 9.9 clamps in the first order)
                assert.is_true(b.lo <= 8) -- lo stays a floor
            end)

            it("adds a swing whose wound lands late to a short answer sampled before it", function()
                -- a short answer (spender_a, 10) at 4.9 bounds the rage before the swing at 5 (the rage taken as in at
                -- the swing: Resources.lua's owe); the wound 0.47 s later adds the swing to it
                obs(Obs.Swing, 2.4, 1, 0, 1)
                obs(Obs.Usable, 4.9, 1, 0, 1)
                obs(Obs.Swing, 5, 1, 2.6, 4)
                I.Fold(5, false)
                I.Settle(5.47)
                obs(Obs.Swing, 5, 1, 0, 1)
                I.Fold(5.47, false)
                local r = VS.Power(fs.RAGE, 6)
                within(9 + 9, r.est)
                assert.is_true(r.hi < 10 + 9 * (1 + I.REGEN_SPREAD))
            end)

            it("nets a usable answer's lift in the swing's window against its late wound", function()
                -- 9 believed; the swing at 5 makes 18; spender_a (10) answers usable at 5.1, before the wound: the
                -- rung lifts 9 to 10 on the swing's rage, so the wound at 5.47 adds 9 - 1: 18, not 19
                obs(Obs.Swing, 2.4, 1, 0, 1)
                obs(Obs.Swing, 5, 1, 2.6, 4)
                obs(Obs.Usable, 5.1, 1, 1, 0)
                I.Fold(5.1, false)
                within(10, VS.Power(fs.RAGE, 5.1).est)
                I.Settle(5.47)
                obs(Obs.Swing, 5, 1, 0, 1)
                I.Fold(5.47, false)
                local r = VS.Power(fs.RAGE, 6)
                within(18, r.est)
                assert.is_true(r.lo <= 18)
            end)

            it("keeps an off-hand swing's lift past a later main-hand wound (dual wield)", function()
                -- truth: 5, the off hand's swing at 4.8 makes 10, spender_a pays it at 5 (0), the main hand's at 5.1
                -- makes 9. Believed 0: the rung lifts 10; the main wound (5.57) owes nothing (after the rung), the
                -- off-hand wound (6.0) pays its 4.5 from the lift: 9, lo below it
                local def = fs.def(fs.new(9))
                def.resources[1].swingOff = 4.5
                boot(def)
                obs(Obs.Swing, 4.8, 2, 1.8, 4)
                obs(Obs.CastSuccess, 5, 1)
                obs(Obs.Swing, 5.1, 1, 2.6, 4)
                I.Fold(5.1, false)
                I.Settle(5.57)
                obs(Obs.Swing, 5.1, 1, 0, 1)
                I.Fold(5.57, false)
                I.Settle(6)
                obs(Obs.Swing, 4.8, 2, 0, 1)
                I.Fold(6, false)
                local r = VS.Power(fs.RAGE, 6)
                within(9, r.est)
                assert.is_true(r.lo <= 9)
            end)

            it("keeps lo a floor with two lifting rungs and a PLAYER_SWING between them (dual wield)", function()
                -- truth 5; the off hand's swing at 4.8 makes 14; spender_a (10) pays at 5 (4); the main hand's swing
                -- at 5.1 makes 13; spender_c (10) answers usable at 5.2; the main wound at 5.57, the off one at 6.0
                local def = fs.def(fs.new(9))
                def.resources[1].swingOff = 9
                boot(def)
                obs(Obs.Swing, 4.8, 2, 1.8, 4)
                obs(Obs.CastSuccess, 5, 1)
                obs(Obs.Swing, 5.1, 1, 2.6, 4)
                obs(Obs.Usable, 5.2, 3, 1, 0)
                I.Fold(5.2, false)
                I.Settle(5.57)
                obs(Obs.Swing, 5.1, 1, 0, 1)
                I.Fold(5.57, false)
                I.Settle(6)
                obs(Obs.Swing, 4.8, 2, 0, 1)
                I.Fold(6, false)
                local r = VS.Power(fs.RAGE, 6)
                assert.is_true(r.lo <= 13, ("lo %.2f, truth 13"):format(r.lo))
            end)

            it("takes a short answer in the frame of a modelled gain (an avoid's refund) as after the gain", function()
                -- 9 believed; spender_a (10) at 5 pays from a rung-lifted 10, then its avoid refunds 8 (the outcome's
                -- modelled gain) and the client answers short in that frame: the answer bounds 8, not the 0 before
                -- the refund (the client answers the frame's net: harness observer.lua M.FRAME)
                obs(Obs.Swing, 2.4, 1, 0, 1)
                obs(Obs.CastSuccess, 5, 1)
                I.Fold(5, false)
                I.ResourceShift(1, 8, 5, Obs.CastSuccess)
                obs(Obs.Usable, 5, 1, 0, 1)
                I.Fold(5, false)
                local r = VS.Power(fs.RAGE, 5)
                within(8, r.est)
                assert.is_true(r.hi < 10 and r.lo <= 8)
            end)

            it("owes nothing to a swing after the rung", function()
                obs(Obs.CastSuccess, 5, 1) -- 0 believed: the rung lifts 10, the pay takes it
                I.Fold(5, false)
                obs(Obs.Swing, 6, 1, 0, 1)
                I.Fold(6, false)
                within(9, VS.Power(fs.RAGE, 6).est)
            end)
        end)

        it("keeps basis default at rest when a rung bounds the interval without moving the estimate", function()
            obs(Obs.Usable, 5, 1, 0, 1) -- spender_a (10) short at 0 rage, out of combat
            I.Fold(5, false)
            local r = VS.Power(fs.RAGE, 5)
            assert.are.same({ 0, "default" }, { r.est, r.basis })
            assert.is_true(r.hi < 10)
        end)

        it("opens the interval down to rest at combat end", function()
            obs(Obs.Usable, 5, 3, 1, 0)
            obs(Obs.CombatEnd, 6)
            I.Fold(6, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 6).lo)
        end)

        it("decays out of combat at the slot's rate down to rest, lo and hi with it, and not in combat", function()
            local def = fs.def(fs.new(9))
            def.resources[1].decay = 2
            boot(def)
            S.Direct(Obs.CombatStart, 2)
            I.Fold(2, false)
            I.ResourceShift(1, 50, 2, Obs.CastSuccess) -- est 50, lo 50, hi 100
            I.Settle(10)
            local r = VS.Power(fs.RAGE, 10)
            assert.are.same({ 50, 50, 100 }, { r.est, r.lo, r.hi }) -- no decay in combat
            S.Direct(Obs.CombatEnd, 10)
            I.Fold(10, false)
            I.Settle(15)
            r = VS.Power(fs.RAGE, 15)
            assert.are.same({ 40, 0, 90, "modelled" }, { r.est, r.lo, r.hi, r.basis }) -- 50 - 2 x 5; lo opened to rest
            I.Settle(40)
            r = VS.Power(fs.RAGE, 40)
            assert.are.same({ 0, 0, 40 }, { r.est, r.lo, r.hi }) -- est stops at rest (0) at 35; hi 100 - 2 x 30
            I.Settle(100)
            assert.are.equal(0, VS.Power(fs.RAGE, 100).hi)
            I.ResourceShift(1, 100, 100, Obs.CastSuccess)
            local t = 100
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.01
                    I.Settle(t)
                end, 2000)
            )
            assert.is_true(VS.Power(fs.RAGE, t).est < 100)
        end)

        it("applies a declared maximum at build until a plain max read overrides it for good", function()
            local def = fs.def(fs.new(9))
            local declared = 105
            def.resources[1].max = function()
                return declared
            end
            boot(def)
            assert.are.equal(105, I.res.max[1])
            declared = 110
            S.Direct(Obs.CombatEnd, 2)
            I.Fold(2, false)
            assert.are.equal(110, I.res.max[1]) -- re-read at combat end while nothing plain was read
            S.Direct(Obs.Read, 3, 1, 120, I.ReadOf.Max)
            I.Fold(3, false)
            assert.are.equal(120, I.res.max[1])
            S.Direct(Obs.CombatEnd, 4)
            I.Fold(4, false)
            assert.are.equal(120, I.res.max[1]) -- the plain read keeps winning
        end)

        it("leaves the estimate unchanged out of combat when the slot's decay is 0", function()
            local def = fs.def(fs.new(9))
            def.resources[1].decay = function()
                return 0
            end
            boot(def)
            I.ResourceShift(1, 50, 2, Obs.CastSuccess)
            S.Direct(Obs.CombatEnd, 3)
            I.Fold(3, false)
            I.Settle(30)
            assert.are.equal(50, VS.Power(fs.RAGE, 30).est)
        end)

        it("pays nothing for an off-hand swing when only the main hand pays", function()
            obs(Obs.Swing, 5, 2, 1.8, 1)
            I.Fold(5, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 5).est)
        end)

        it("pays each hand its own value when both hands pay it, and calibrates against their sum", function()
            local def = fs.def(fs.new(9))
            def.resources[1].swingOff = 4.5
            boot(def)
            obs(Obs.Swing, 5, 1, 2.6, 4) -- each hand's swing, then its landed wound
            obs(Obs.Swing, 5, 1, 0, 1)
            obs(Obs.Swing, 5.5, 2, 1.8, 4)
            obs(Obs.Swing, 5.5, 2, 0, 1)
            I.Fold(5.5, false)
            assert.are.equal(13.5, VS.Power(fs.RAGE, 6).est)
            within(9 / 2.6 + 4.5 / 1.8, I.SwingPerSecond(1))
            within(9 / 2.6 + 4.5 / 1.8, VS.Regen(fs.RAGE, 6).est)
            obs(Obs.Swing, 7.3, 2, 0, 1)
            I.Fold(7.3, false)
            assert.are.equal(18, VS.Power(fs.RAGE, 7.3).est)
        end)

        it("allocates nothing paying and projecting two hands", function()
            local def = fs.def(fs.new(9))
            def.resources[1].swingOff = 4.5
            boot(def)
            local t = 5
            local bytes = alloc.bytes(function(i)
                t = t + 0.1
                obs(Obs.Swing, t, i % 2 + 1, 2, 1)
                I.Fold(t, false)
                VS.Power(fs.RAGE, t)
                VS.Regen(fs.RAGE, t)
            end, 2000)
            assert.are.equal(0, bytes)
        end)

        it("answers an untracked power type with the unknown record", function()
            local u = VS.Power(99, 1)
            assert.are.same({ 0, "unknown" }, { u.conf, u.basis })
        end)
    end)

    describe("aura-gated regen (rage, regen_aura_a: 1 a second while its aura is up)", function()
        local REGEN_AURA_A = 3 -- the aura index

        before_each(function()
            local def = fs.def(fs.new(9))
            def.auras[REGEN_AURA_A] = { key = "regen_aura_a", id = 1021 }
            def.auraIds[REGEN_AURA_A] = { 1021 }
            def.resources[1].auraRegen = {
                { aura = "regen_aura_a", interval = 1, value = 1 },
                { aura = "not_tracked", interval = 1, value = 5 }, -- no such aura: ignored
            }
            boot(def)
            I.Fold(10, false) -- the clock starts at 10
        end)

        it("adds value at each interval after the aura's application while it is believed up", function()
            I.AuraModel(1, REGEN_AURA_A, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
            I.Settle(15.5)
            assert.are.equal(5, VS.Power(fs.RAGE, 15.5).est) -- ticks at 11, 12, 13, 14, 15
            assert.are.equal(10, VS.Power(fs.RAGE, 25).est) -- projected: 16 to 20, none after the expiry
            I.Settle(25)
            local r = VS.Power(fs.RAGE, 30)
            assert.are.same({ 10, 10 }, { r.est, r.lo })
            assert.are.equal(10, I.res.pinDelta[1]) -- kept out of the next regen measurement
            assert.are.equal(1, I.res.auraRegen.n)
        end)

        it("adds nothing while the aura is down", function()
            I.Settle(20)
            assert.are.equal(0, VS.Power(fs.RAGE, 25).est)
        end)

        it("stops when the aura is believed gone early", function()
            I.AuraModel(1, REGEN_AURA_A, 10, 20, 1, 10, 0)
            I.Settle(12.5)
            I.AuraModel(1, REGEN_AURA_A, 0, 0, 0, 12.5, 0) -- gone at 12.5 (expiry 0: down)
            I.Settle(20)
            assert.are.equal(2, VS.Power(fs.RAGE, 20).est)
        end)

        it("pauses the out-of-combat decay while an aura-gated entry's aura is up, resumes after it expires", function()
            local def = fs.def(fs.new(9))
            def.auras[REGEN_AURA_A] = { key = "regen_aura_a", id = 1021 }
            def.auraIds[REGEN_AURA_A] = { 1021 }
            def.resources[1].decay = 2
            def.resources[1].auraRegen = { { aura = "regen_aura_a", interval = 1, value = 1, pausesDecay = true } }
            boot(def)
            I.Fold(10, false)
            I.ResourceShift(1, 20, 10, Obs.CastSuccess) -- est 20, out of combat
            I.AuraModel(1, REGEN_AURA_A, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
            I.Settle(15)
            assert.are.equal(25, VS.Power(fs.RAGE, 15).est) -- 5 ticks, no decay
            I.Settle(22)
            assert.are.equal(26, VS.Power(fs.RAGE, 22).est) -- 5 more ticks, then 2 s x 2/s after the expiry
        end)

        it("does not pause the decay for an aura entry without `pausesDecay`", function()
            local def = fs.def(fs.new(9))
            def.auras[REGEN_AURA_A] = { key = "regen_aura_a", id = 1021 }
            def.auraIds[REGEN_AURA_A] = { 1021 }
            def.resources[1].decay = 2
            def.resources[1].auraRegen = { { aura = "regen_aura_a", interval = 1, value = 1 } }
            boot(def)
            I.Fold(10, false)
            I.ResourceShift(1, 20, 10, Obs.CastSuccess) -- est 20, out of combat
            I.AuraModel(1, REGEN_AURA_A, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
            I.Settle(15)
            assert.are.equal(15, VS.Power(fs.RAGE, 15).est) -- 5 ticks and 5 s x 2/s of decay
        end)

        it("lands the tick at the expiry: a 10 s aura ticking 1 a second lands 10", function()
            I.AuraModel(1, REGEN_AURA_A, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
            assert.are.equal(5, VS.Power(fs.RAGE, 15).est) -- (10, 15]: 11 to 15
            assert.are.equal(10, VS.Power(fs.RAGE, 20).est) -- (10, 20]: 11 to 20, the expiry's tick too
            assert.are.equal(10, VS.Power(fs.RAGE, 30).est) -- (10, 30]: nothing after it
        end)

        it("leaves decay at the full rate when the tick aura is down or already expired", function()
            local def = fs.def(fs.new(9))
            def.auras[REGEN_AURA_A] = { key = "regen_aura_a", id = 1021 }
            def.auraIds[REGEN_AURA_A] = { 1021 }
            def.resources[1].decay = 2
            def.resources[1].auraRegen = { { aura = "regen_aura_a", interval = 1, value = 1 } }
            boot(def)
            I.Fold(10, false)
            I.ResourceShift(1, 50, 10, Obs.CastSuccess) -- est 50, out of combat, aura never applied
            I.Settle(15)
            assert.are.equal(40, VS.Power(fs.RAGE, 15).est) -- 2/s x 5
            I.AuraModel(1, REGEN_AURA_A, 5, 12, 1, 15, 0) -- applied at 5, expired at 12, before this advance
            I.Settle(20)
            assert.are.equal(30, VS.Power(fs.RAGE, 20).est) -- still 2/s x 5
        end)

        it("credits a plain periodic entry only in combat, from the combat start, and only with its talent", function()
            local def = fs.def(fs.new(9))
            def.resources[1].auraRegen = { { talent = "talent_a", interval = 3, value = 1 } }
            boot(def)
            I.Fold(10, false)
            I.Settle(20)
            assert.are.equal(0, VS.Power(fs.RAGE, 20).est) -- out of combat
            S.Direct(Obs.CombatStart, 21)
            I.Fold(21, false)
            I.Settle(28)
            assert.are.equal(0, VS.Power(fs.RAGE, 28).est) -- in combat, but the talent is not taken
            I.SetTalentRank(1, 1)
            I.Settle(31)
            assert.are.equal(1, VS.Power(fs.RAGE, 31).est) -- the tick at 30 (combat start 21 + 3 x 3)
            assert.are.equal(2, VS.Power(fs.RAGE, 33.5).est) -- projected: 33
            S.Direct(Obs.CombatEnd, 34)
            I.Fold(34, false)
            I.Settle(40)
            assert.are.equal(2, VS.Power(fs.RAGE, 40).est) -- 33 was the last tick
            S.Direct(Obs.CombatStart, 50)
            I.Fold(50, false)
            local t = 50
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.1
                    I.Settle(t)
                    VS.Power(fs.RAGE, t + 0.5)
                end, 2000)
            )
        end)

        it("credits a plain periodic entry after a build in combat, from the build", function()
            local def = fs.def(fs.new(9))
            def.resources[1].auraRegen = { { interval = 3, value = 1 } }
            boot(def)
            I.inCombat = true -- a /reload or a spec change in combat: no CombatStart comes
            I.Build(def, 10)
            I.Fold(10, false)
            I.Settle(16.5)
            assert.are.equal(2, VS.Power(fs.RAGE, 16.5).est) -- ticks at 13 and 16
        end)

        it("allocates nothing advancing or projecting through an entry", function()
            I.AuraModel(1, REGEN_AURA_A, 10, 1e9, 1, 10, 0)
            local t = 10
            local bytes = alloc.bytes(function()
                t = t + 0.1
                I.Settle(t)
                VS.Power(fs.RAGE, t + 0.5)
            end, 10000)
            assert.are.equal(0, bytes)
        end)
    end)

    describe("stepped decay (rage: 1.25 lost at the start of each 1 s window out of combat)", function()
        local REGEN_AURA_A = 3 -- the aura index

        before_each(function()
            local def = fs.def(fs.new(9))
            def.auras[REGEN_AURA_A] = { key = "regen_aura_a", id = 1021 }
            def.auraIds[REGEN_AURA_A] = { 1021 }
            def.resources[1].decay = 1.25
            def.resources[1].decayInterval = function() -- a function, as a class file's meta table declares it
                return 1
            end
            def.resources[1].auraRegen = { { aura = "regen_aura_a", interval = 1, value = 1, pausesDecay = true } }
            boot(def)
            S.Direct(Obs.CombatStart, 2)
            I.Fold(2, false)
        end)

        -- 50 rage in combat from 2; the combat ends at 10.
        local function combatEnd()
            I.ResourceShift(1, 50, 2, Obs.CastSuccess)
            I.Settle(10)
            S.Direct(Obs.CombatEnd, 10)
            I.Fold(10, false)
        end

        it("takes the first quantum at the combat end, then one at each window's start, down to rest", function()
            combatEnd()
            assert.are.equal(48.75, VS.Power(fs.RAGE, 10).est) -- at once
            I.Settle(10.5)
            assert.are.equal(48.75, VS.Power(fs.RAGE, 10.5).est)
            I.Settle(11)
            assert.are.equal(47.5, VS.Power(fs.RAGE, 11).est)
            I.Settle(12.9)
            local r = VS.Power(fs.RAGE, 12.9)
            assert.are.same({ 46.25, 0, 96.25, "modelled" }, { r.est, r.lo, r.hi, r.basis }) -- beats at 10, 11, 12
            assert.are.same({ 13, 12 }, { I.res.decayNext[1], VS.DecayAnchor(fs.RAGE) })
            I.Settle(60)
            assert.are.same({ 0, 0, 0 }, { VS.Power(fs.RAGE, 60).est, I.res.decayNext[1], VS.DecayAnchor(fs.RAGE) })
        end)

        it("lands regen_aura_a's tenth tick at its expiry, then the first quantum at once: 10 - 1.25", function()
            S.Direct(Obs.CombatEnd, 5)
            I.Fold(5, false) -- at rest (0): no quantum
            I.Settle(10)
            I.AuraModel(1, REGEN_AURA_A, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
            I.Settle(15)
            assert.are.same({ 5, 0 }, { VS.Power(fs.RAGE, 15).est, I.res.decayNext[1] }) -- paused while it is up
            I.Settle(20)
            assert.are.same({ 8.75, 21 }, { VS.Power(fs.RAGE, 20).est, I.res.decayNext[1] }) -- the tick, then the step
            I.Settle(21)
            assert.are.equal(7.5, VS.Power(fs.RAGE, 21).est)
        end)

        it("pauses for a tick aura applied while decaying and re-anchors at its expiry", function()
            combatEnd()
            I.Settle(12.5) -- 46.25: beats at 10, 11, 12
            I.AuraModel(1, REGEN_AURA_A, 13, 23, 1, 12.5, 0) -- applied at 13, expires at 23
            I.Settle(13)
            assert.are.same({ 46.25, 0 }, { VS.Power(fs.RAGE, 13).est, I.res.decayNext[1] }) -- no beat at 13
            I.Settle(18)
            assert.are.equal(51.25, VS.Power(fs.RAGE, 18).est) -- ticks at 14 to 18
            I.Settle(23)
            assert.are.same({ 55, 24 }, { VS.Power(fs.RAGE, 23).est, I.res.decayNext[1] }) -- 19 to 23, then a step
            I.Settle(24)
            assert.are.equal(53.75, VS.Power(fs.RAGE, 24).est)
        end)

        it("stops at a combat start and front-loads again at the next combat end", function()
            combatEnd()
            I.Settle(11.5) -- 47.5
            S.Direct(Obs.CombatStart, 11.5)
            I.Fold(11.5, false)
            assert.are.equal(0, I.res.decayNext[1])
            I.Settle(20)
            assert.are.equal(47.5, VS.Power(fs.RAGE, 20).est) -- no quantum in combat
            S.Direct(Obs.CombatEnd, 20.5)
            I.Fold(20.5, false)
            assert.are.same({ 46.25, 21.5 }, { VS.Power(fs.RAGE, 20.5).est, I.res.decayNext[1] })
        end)

        it("stamps each quantum's modelled sample at its beat", function()
            combatEnd()
            local m = I.res.power[1].last.modelled
            assert.are.same({ 48.75, 10 }, { m.v, m.t }) -- the front-loaded one, at the combat end
            I.Settle(11.9)
            assert.are.same({ 47.5, 11 }, { m.v, m.t })
            I.Settle(12.9)
            assert.are.same({ 46.25, 12 }, { m.v, m.t })
        end)

        it("clamps the last quantum at rest from an estimate not a multiple of it, the clamp in pinDelta", function()
            I.ResourceShift(1, 49, 2, Obs.CastSuccess)
            I.Settle(10)
            S.Direct(Obs.CombatEnd, 10)
            I.Fold(10, false)
            local before = I.res.pinDelta[1] + 1.25 -- before the front-loaded quantum
            I.Settle(48.5) -- 39 quanta at 10 to 48: 0.25 left
            assert.are.same({ 0.25, 49 }, { I.res.est0[1], I.res.decayNext[1] })
            I.Settle(60)
            assert.are.same({ 0, 0 }, { I.res.est0[1], I.res.decayNext[1] }) -- the 40th lost 0.25, not 1.25
            assert.are.equal(before - 49, I.res.pinDelta[1]) -- exactly the 49 lost, out of the regen measurement
        end)

        it("starts from a rise above rest out of combat, and allocates nothing over combat cycles", function()
            S.Direct(Obs.CombatEnd, 5)
            I.Fold(5, false)
            I.Settle(6)
            I.ResourceShift(1, 20, 6, Obs.CastSuccess) -- out of combat, at the clock
            I.Settle(6.5)
            assert.are.same({ 18.75, 7 }, { VS.Power(fs.RAGE, 6.5).est, I.res.decayNext[1] }) -- the first beat at 6
            local t = 10
            assert.are.equal(
                0,
                alloc.bytes(function(i)
                    t = t + 0.1
                    if i % 50 == 0 then
                        S.Direct(i % 100 == 0 and Obs.CombatEnd or Obs.CombatStart, t)
                        I.Fold(t, false)
                        I.ResourceShift(1, 30, t, Obs.CastSuccess)
                    end
                    I.Settle(t)
                    VS.Power(fs.RAGE, t)
                    VS.DecayAnchor(fs.RAGE)
                end, 2000)
            )
        end)
    end)

    describe("a resource resting at its maximum, and a fractional cost (mana, 0.55 of the maximum)", function()
        local MANA, FORM, BIG = 0, 1, 2
        local def

        before_each(function()
            def = {
                abilities = { { key = "form", spend = 0.55 }, { key = "big", spend = 1200 } },
                abilityIds = { { 768 }, { 1001 } },
                abilitySlot = { 1, 1 },
                resources = { { key = "mana", type = MANA, token = "MANA", max = 100, rest = true } },
                auras = { { key = "clearcasting", id = 16870 } },
                auraIds = { { 16870 } },
                talents = {},
                units = { "player", "target" },
            }
            boot(def)
        end)

        local function maxRead(t, v)
            obs(Obs.Read, t, 1, v, I.ReadOf.Max)
            I.Fold(t, false)
        end

        it("seeds at its declared maximum, and a plain maximum read moves the rest and raises the estimate", function()
            assert.are.same({ 100, 100, 100 }, { VS.Power(MANA, 1).est, I.res.rest[1], I.res.max[1] })
            maxRead(2, 1200)
            local m = VS.Power(MANA, 2)
            assert.are.same({ 1200, 1200, 1200, 1200 }, { m.est, m.hi, I.res.rest[1], I.res.max[1] })
            assert.are.equal(1100, I.res.pinDelta[1]) -- kept out of the next regen measurement
        end)

        it("raises the estimate only by an increase; a lower maximum only caps it", function()
            I.ResourceShift(1, -60, 2, Obs.CastSuccess) -- 40 of 100
            maxRead(3, 1200)
            assert.are.equal(1140, VS.Power(MANA, 3).est)
            maxRead(4, 1000)
            assert.are.same({ 1000, 1000, 1000 }, { VS.Power(MANA, 4).est, I.res.max[1], I.res.rest[1] })
            assert.are.equal(-60 + 1100 - 140, I.res.pinDelta[1]) -- the capped-away 140 kept out of the regen measurement
        end)

        it("follows a maximum raised through maxMods at combat end, and caps at a lowered one", function()
            local on = false
            def.resources[1].maxMods = {
                {
                    pct = 0.2,
                    when = function()
                        return on
                    end,
                },
            }
            boot(def)
            on = true
            obs(Obs.CombatEnd, 2)
            I.Fold(2, false)
            assert.are.same({ 120, 120, 120 }, { I.res.est0[1], I.res.hi0[1], I.res.max[1] })
            on = false
            obs(Obs.CombatEnd, 3)
            I.Fold(3, false)
            assert.are.same({ 100, 100, 100 }, { I.res.est0[1], I.res.hi0[1], I.res.max[1] })
        end)

        it("prices a cost below 1 as that fraction of the maximum; a cost of 1 or more is unchanged", function()
            within(55, I.CostOf(FORM)) -- 0.55 x the declared 100
            assert.are.equal(1200, I.CostOf(BIG))
            maxRead(2, 1200)
            assert.are.same({ 660, 1200 }, { I.CostOf(FORM), I.CostOf(BIG) })
        end)

        it("pins the ladder at 660 when the form reads usable and below 660 when it reads short", function()
            maxRead(2, 1200)
            I.ResourceShift(1, -1000, 2, Obs.CastSuccess) -- 200 believed
            obs(Obs.Usable, 3, FORM, 1, 0)
            I.Fold(3, false)
            local m = VS.Power(MANA, 3)
            assert.are.same({ 660, 660 }, { m.est, m.lo })
            obs(Obs.Usable, 4, FORM, 0, 1)
            I.Fold(4, false)
            within(660 - I.EPS, VS.Power(MANA, 4).hi)
        end)

        it("pays 660 at the cast's cost step, and 330 under a cost modifier pct = -0.5", function()
            maxRead(2, 1200)
            obs(Obs.CastSuccess, 3, FORM)
            I.Fold(3, false)
            assert.are.equal(540, VS.Power(MANA, 3).est)
            def.resources[1].costMods = { { aura = "clearcasting", pct = -0.5 } }
            I.Build(def, 4)
            maxRead(4, 1200)
            I.AuraModel(1, 1, 4, 19, 1, 4, Obs.CastSuccess, false)
            I.Settle(5)
            assert.are.equal(330, I.CostOf(FORM))
            obs(Obs.CastSuccess, 6, FORM)
            I.Fold(6, false)
            assert.are.equal(870, VS.Power(MANA, 6).est)
        end)

        it("allocates nothing over 1000 maximum reads (setMax) and fractional casts", function()
            local t = 2
            local bytes = alloc.bytes(function(i)
                t = t + 1
                maxRead(t, i % 2 == 0 and 1200 or 1300)
                obs(Obs.CastSuccess, t + 0.5, FORM)
                I.Fold(t + 0.5, false)
                VS.Power(MANA, t + 0.6)
            end, 1000)
            assert.are.equal(0, bytes)
        end)

        it("leaves a slot resting at 0 (rage) unchanged by a maximum read", function()
            boot(fs.def(fs.new(9)))
            I.ResourceShift(1, 30, 2, Obs.CastSuccess)
            obs(Obs.Read, 3, 1, 120, I.ReadOf.Max)
            I.Fold(3, false)
            assert.are.same({ 30, 0, 120 }, { VS.Power(fs.RAGE, 3).est, I.res.rest[1], I.res.max[1] })
        end)
    end)

    describe("a never-plain regenerating slot (mana): the modelled floor", function()
        local MANA, SEAL, BIG = 0, 1, 2
        local function bootMana()
            boot({
                abilities = { { key = "seal", spend = 150 }, { key = "big", spend = 305 } },
                abilityIds = { { 1001 }, { 1002 } },
                abilitySlot = { 1, 1 },
                resources = {
                    {
                        key = "mana",
                        type = MANA,
                        token = "MANA",
                        max = 3737,
                        rest = true,
                        fsr = { spirit = 13.65, mp5 = 8.25 },
                    },
                },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
            I.res.regL[1], I.res.spL[1] = 8.25, 13.65 -- the out-of-combat read made both parts exact
            I.res.regH[1], I.res.spH[1] = 8.25, 13.65
            I.Settle(10)
        end

        it("keeps the rest assumption through a usable answer heard before the plain maximum", function()
            boot({ -- the declared maximum is the default 100 until the read: a usable 450 lifts lo0 past it first
                abilities = { { key = "big", spend = 450 } },
                abilityIds = { { 1001 } },
                abilitySlot = { 1 },
                resources = {
                    { key = "mana", type = MANA, token = "MANA", rest = true, fsr = { spirit = 13, mp5 = 2 } },
                },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
            I.Settle(10)
            obs(Obs.Usable, 10, 1, 1, 0)
            obs(Obs.Read, 10, 1, 5000, I.ReadOf.Max)
            I.Fold(10, false)
            assert.are.same({ 5000, 5000 }, { VS.Power(MANA, 10).lo, VS.Power(MANA, 10).est })
        end)

        it("drops the floor to the ladder's at a short answer below it", function()
            bootMana()
            obs(Obs.Usable, 10, BIG, 0, 1) -- short of 305: the rest was wrong
            I.Fold(10, false)
            local r = VS.Power(MANA, 10)
            assert.is_true(r.lo < 305 and r.est < 305 and r.hi < 305)
            assert.are.equal(0, I.res.over[1]) -- the measured floor alone: what regen gave since the build
        end)

        it(
            "follows a 30 s fight's spends and regen, where the measured floor sat at the dearest usable cost",
            function()
                -- the Retribution collapse (Paladin lane, task 9): a seal (150) every 3 s, the dearest spell (305) usable
                -- at each; the truth is the rest less the spends plus the window-aware regen (8.25 inside, 21.9 after)
                bootMana()
                obs(Obs.CombatStart, 10, 0, 0, 0)
                I.Fold(10, false)
                local truth, last = 3737, 10
                for k = 0, 9 do
                    local t = 10 + 3 * k
                    truth = math.min(3737, truth + 8.25 * (t - last)) -- inside the window since the last spend (3 s < 5)
                    last = t
                    obs(Obs.Usable, t, BIG, 1, 0)
                    obs(Obs.CastSuccess, t, SEAL)
                    I.Fold(t, false)
                    truth = truth - 150
                    local r = VS.Power(MANA, t)
                    assert.is_true(
                        r.lo <= truth + 1e-6 and r.lo >= truth - 1e-6,
                        ("lo %.1f truth %.1f"):format(r.lo, truth)
                    )
                end
                assert.is_true(I.res.lo0[1] < 400) -- the measured floor alone: the dearest usable cost and what regen adds
                within(truth + 8.25 * 5 + 21.9 * 5, VS.Power(MANA, last + 10).lo) -- then the window closes at last + 5
            end
        )

        for _, plain in ipairs({ false, true }) do
            it(
                "keeps a 375 spender affordable against a 2000+ pool (the Enhancement Fire Nova case"
                    .. (plain and ", after a plain read)" or ", never read)"),
                function()
                    bootMana()
                    if plain then
                        obs(Obs.Read, 10, 1, 2600, I.ReadOf.Resource) -- a plain pre-combat read: exact
                    end
                    obs(Obs.CombatStart, 10, 0, 0, 0)
                    I.Fold(10, false)
                    local truth, last = plain and 2600 or 3737, 10
                    for k = 1, 6 do -- 375 every 4 s, usable at each: the floor stays above the cost
                        local t = 10 + 4 * k
                        -- no spend before the first cast: the full rate, then the window's mp5 part (4 s < 5)
                        truth = math.min(3737, truth + (k == 1 and 21.9 or 8.25) * (t - last))
                        last = t
                        obs(Obs.Usable, t, BIG, 1, 0)
                        S.Direct(Obs.CastSuccess, t, BIG, 375, 1)
                        I.Fold(t, false)
                        truth = truth - 375
                        local r = VS.Power(MANA, t)
                        assert.is_true(r.lo > 375 and r.lo <= truth + 1e-6, ("lo %.1f truth %.1f"):format(r.lo, truth))
                    end
                end
            )
        end

        it("opens the five-second window at a paid cast only, not at a free one", function()
            bootMana()
            obs(Obs.CombatStart, 10, 0, 0, 0)
            S.Direct(Obs.CastSuccess, 11, SEAL, 0, 1) -- priced 0 when heard (a free-cast aura): no spend, no window
            I.Fold(11, false)
            assert.are.equal(0, I.res.fsrUntil[1])
            S.Direct(Obs.CastSuccess, 12, SEAL, 150, 1)
            I.Fold(12, false)
            assert.are.equal(17, I.res.fsrUntil[1])
            within(3737 - 150, VS.Power(MANA, 12).est)
        end)
    end)

    describe("the five-second rule (C3: mana's `fsr`, spirit 10/s and mp5 2/s declared)", function()
        local MANA = 0

        before_each(function()
            boot({
                abilities = {},
                abilityIds = {},
                abilitySlot = {},
                resources = {
                    {
                        key = "mana",
                        type = MANA,
                        token = "MANA",
                        max = 1000,
                        rest = true,
                        fsr = { spirit = 10, mp5 = 2 },
                    },
                },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
            I.Settle(10)
        end)

        local function read(t, v)
            obs(Obs.Read, t, 1, v, I.ReadOf.Resource)
            I.Fold(t, false)
        end

        it("opens a 5 s window at our own spend: only the mp5 part regenerates in it", function()
            I.ResourceShift(1, -500, 10, Obs.CastSuccess) -- 500 at 10, the window to 15
            within(510, VS.Power(MANA, 15).est) -- 2/s for 5 s
            within(534, VS.Power(MANA, 17).est) -- then 12/s
            assert.are.same({ 2, 12, 2 }, {
                VS.Regen(MANA, 12).est,
                VS.Regen(MANA, 16).est,
                VS.Regen(MANA, 16, true).est, -- casting: the mp5 part
            })
            -- the client's pair ignores the window (the sim applies it from FsrUntil): not casting, both parts
            assert.are.same({ 12, 15 }, { VS.Regen(MANA, 12, VS.NOT_CASTING).est, VS.FsrUntil(MANA) })
            assert.is_nil(VS.FsrUntil(99))
            I.Settle(13)
            I.ResourceShift(1, -100, 13, Obs.CastSuccess) -- a second spend: the window to 18
            I.Settle(20)
            within(500 + 6 - 100 + 2 * 7 + 10 * 2, VS.Power(MANA, 20).est)
        end)

        it("calibrates each part in its own state, across windows", function()
            read(10, 500)
            read(12, 530) -- outside: 15/s, the spirit part (30 - 2 x 2) / 2 = 13
            within(10 + I.ALPHA * 3, I.res.spE[1])
            assert.are.equal(2, I.res.regE[1])
            I.ResourceShift(1, -100, 12, Obs.CastSuccess) -- the window to 17
            read(14, 436) -- inside: (436 - 530 + 100) / 2 = 3/s, the mp5 part
            local mp5 = 2 + I.ALPHA * 1
            within(mp5, I.res.regE[1])
            within(10 + I.ALPHA * 3, I.res.spE[1])
            local spirit = 10 + I.ALPHA * 3
            read(20, 436 + mp5 * 6 + 12 * 3) -- 3 s outside: (gain - mp5 x 6) / 3 = 12
            within(spirit + I.ALPHA * (12 - spirit), I.res.spE[1])
            within(mp5, I.res.regE[1])
            within(mp5 + spirit + I.ALPHA * (12 - spirit), VS.Regen(MANA, 20).est)
        end)

        it("takes no measurement from less than PIN_GAP outside the window (0 < pinB < PIN_GAP)", function()
            read(10, 500)
            I.ResourceShift(1, -100, 10, Obs.CastSuccess) -- the window to 15
            read(15.5, 400 + 2 * 5 + 30) -- 0.5 s outside: no part moves
            assert.are.same({ 2, 10 }, { I.res.regE[1], I.res.spE[1] })
        end)

        it("reads both parts out of combat: not casting is spirit + mp5, casting the mp5 part", function()
            local api = fake.new()
            I.api = api
            VS.Start(api)
            local function poll(t)
                api.ctl.Tick(t)
                S.RunPolls(t)
                I.Fold(t, false)
            end
            api.ctl.regen[MANA] = { 14, 3 }
            poll(105)
            assert.are.same({ 3, 11 }, { I.res.regE[1], I.res.spE[1] })
            assert.are.same({ 14, 3 }, { VS.Regen(MANA, 105).est, VS.Regen(MANA, 105, true).est })
            api.ctl.regen[MANA] = { 0, 0 } -- a total 0 for a slot at rest at its maximum: no news
            poll(110)
            assert.are.equal(14, VS.Regen(MANA, 110).est)
        end)

        -- The lower bound mana floors (D7, `mana.pct>=N`) are judged on: the build assumes rest, the floor too (mana is
        -- secret even out of combat, so nothing measures it), and only a measurement below it drops it.
        it("rests a fresh boot's floor at the maximum, a secret read never in the maths", function()
            within(1000, VS.Power(MANA, 10).lo)
            local api = fake.new() -- its clock at 100
            I.api = api
            VS.Start(api)
            api.ctl.powerMax[MANA] = 1000
            api.ctl.regen[MANA] = { 15, 3 } -- exact once read: spirit 12 + mp5 3
            -- ctl.power[MANA] unset: every UnitPower answers the SECRET proxy, which raises on any compare or maths
            api.ctl.Tick(101)
            S.RunPolls(101)
            I.Fold(101, false)
            assert.are.same({ 1000, 1000, 1000 }, { VS.Power(MANA, 101).lo, VS.Power(MANA, 101).est, I.res.max[1] })
        end)

        it(
            "carries the rested bound through combat: lowered by our spend, the window at the mp5 part's low edge",
            function()
                I.Settle(120)
                assert.are.equal(1000, VS.Power(MANA, 120).lo)
                obs(Obs.CombatStart, 120, 0, 0, 0)
                I.Fold(120, false)
                I.ResourceShift(1, -300, 120, Obs.CastSuccess) -- the window to 125
                assert.are.equal(700, VS.Power(MANA, 120).lo)
                within(700 + 2 * 0.9 * 5, VS.Power(MANA, 125).lo)
                within(700 + 2 * 0.9 * 5 + 12 * 0.9 * 2, VS.Power(MANA, 127).lo)
            end
        )

        it("learns an mp5 part declared 0 (or read 0) from a measurement inside the window", function()
            boot({
                abilities = {},
                abilityIds = {},
                abilitySlot = {},
                resources = {
                    {
                        key = "mana",
                        type = MANA,
                        token = "MANA",
                        max = 1000,
                        rest = true,
                        fsr = { spirit = 10, mp5 = 0 },
                    },
                },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
            I.Settle(10)
            read(10, 500)
            I.ResourceShift(1, -100, 10, Obs.CastSuccess) -- the window to 15
            read(12, 400 + 4) -- 2/s inside: the mp5 part
            within(I.ALPHA * 2, I.res.regE[1])
        end)

        it("allocates nothing over 1000 spends, advances and projections", function()
            local t = 10
            local bytes = alloc.bytes(function()
                t = t + 1
                I.ResourceShift(1, -1, t, Obs.CastSuccess)
                I.Settle(t + 0.5)
                VS.Power(MANA, t + 6)
                VS.Regen(MANA, t + 6)
            end, 1000)
            assert.are.equal(0, bytes)
        end)
    end)

    describe("a regen `mult` (C3b: energy 10/s, x2 while rate_aura is up)", function()
        local RATE_AURA = 1

        before_each(function()
            boot({
                abilities = {},
                abilityIds = {},
                abilitySlot = {},
                resources = {
                    {
                        key = "energy",
                        type = ENERGY,
                        token = "ENERGY",
                        max = 200,
                        rest = true,
                        regen = 10,
                        mult = { { aura = "rate_aura", mult = 2 }, { aura = "not_tracked", mult = 5 } },
                    },
                },
                auras = { { key = "rate_aura", id = 1021 } },
                auraIds = { { 1021 } },
                talents = {},
                units = { "player", "target" },
            })
            I.Settle(10)
            I.ResourceShift(1, -200, 10, Obs.CastSuccess) -- 0 at 10
            I.AuraModel(1, RATE_AURA, 10, 15, 1, 10, 0) -- applied at 10, expires at 15
        end)

        it("scales the rate while its aura is up", function()
            within(40, VS.Power(ENERGY, 12).est)
            within(100 + 30, VS.Power(ENERGY, 18).est) -- 20/s to 15, then 10/s
            assert.are.same({ 20, 10 }, { VS.Regen(ENERGY, 12).est, VS.Regen(ENERGY, 16).est })
            I.Settle(18)
            within(130, I.res.est0[1])
        end)

        it("calibrates the unscaled rate: a measurement under the aura is divided by its mult", function()
            obs(Obs.Read, 10, 1, 0, I.ReadOf.Resource)
            I.Fold(10, false)
            obs(Obs.Read, 12, 1, 48, I.ReadOf.Resource) -- 24/s under x2: 12/s unscaled
            I.Fold(12, false)
            within(10 + I.ALPHA * 2, I.res.regE[1])
            within(2 * (10 + I.ALPHA * 2), VS.Regen(ENERGY, 12).est)
        end)

        it("calibrates across the aura's expiry between two pins (x2 to 15, then x1)", function()
            obs(Obs.Read, 10, 1, 0, I.ReadOf.Resource)
            I.Fold(10, false)
            obs(Obs.Read, 18, 1, 12 * (2 * 5 + 3), I.ReadOf.Resource) -- 12/s unscaled over 13 weighted seconds
            I.Fold(18, false)
            within(10 + I.ALPHA * 2, I.res.regE[1])
            within(10 + I.ALPHA * 2, VS.Regen(ENERGY, 18).est)
        end)

        it("an out-of-combat regen read taken under the aura is stored unscaled", function()
            obs(Obs.Read, 12, 1, 24, I.ReadOf.Regen) -- the game's 24/s already includes the x2
            I.Fold(12, false)
            assert.are.same({ 12, 12 }, { I.res.decl[1], I.res.regE[1] })
            assert.are.same({ 24, 12 }, { VS.Regen(ENERGY, 12).est, VS.Regen(ENERGY, 16).est })
        end)
    end)

    it("ignores a regen `mult` of 0 or less (the out-of-combat read divides by it)", function()
        boot({
            abilities = {},
            abilityIds = {},
            abilitySlot = {},
            resources = {
                {
                    key = "energy",
                    type = ENERGY,
                    token = "ENERGY",
                    max = 200,
                    rest = true,
                    regen = 10,
                    mult = { { aura = "rate_aura", mult = 0 }, { aura = "rate_aura", mult = -1 } },
                },
            },
            auras = { { key = "rate_aura", id = 1021 } },
            auraIds = { { 1021 } },
            talents = {},
            units = { "player", "target" },
        })
        I.Settle(10)
        I.AuraModel(1, 1, 10, 15, 1, 10, 0)
        assert.are.same({ 0, false }, { I.res.regenMult.n, I.res.shaped[1] })
        obs(Obs.Read, 12, 1, 12, I.ReadOf.Regen)
        I.Fold(12, false)
        assert.are.same({ 12, 12 }, { I.res.decl[1], VS.Regen(ENERGY, 12).est })
    end)

    describe("a swing entry gated on a player aura (swings pay only while form_a is up)", function()
        local GATE, SPENDER_C = 3, 3 -- the aura index; fs.def's ability index of spender_c (10 rage)

        local function gated(aura)
            local def = fs.def(fs.new(9))
            def.auras[GATE] = { key = "form_a", id = 1041 }
            def.auraIds[GATE] = { 1041 }
            def.resources[1].swingAura = aura
            boot(def)
            I.Fold(10, false)
        end

        local function swing(t)
            obs(Obs.Swing, t, 1, 2.5, 4)
            obs(Obs.Swing, t, 1, 0, 1)
            I.Fold(t, false)
            return VS.Power(fs.RAGE, t).est
        end

        it("pays only while the aura is believed up: never applied, applied (as a `now` writes it), expired", function()
            gated("form_a")
            assert.are.equal(0, swing(11))
            I.AuraModel(1, GATE, 12, 30, 1, 12, Obs.CastSuccess, false) -- the shift's applyBuff
            assert.are.equal(9, swing(13.5))
            assert.are.equal(18, swing(16))
            assert.are.equal(18, swing(31)) -- past the believed expiry
        end)

        it("pays nothing when the gate names an untracked aura, and as before without a gate", function()
            gated("form_b_test")
            I.AuraModel(1, GATE, 12, 30, 1, 12, Obs.CastSuccess, false)
            assert.are.equal(0, swing(13.5))
            gated(nil)
            assert.are.equal(9, swing(11))
        end)

        it("out of the aura: no swing rate to calibrate against, and a zero-width pin on the ladder", function()
            gated("form_a")
            swing(11) -- a speed to divide by
            I.AuraModel(1, GATE, 12, 30, 1, 12, Obs.CastSuccess, false)
            I.Settle(12)
            within(9 / 2.5, I.SwingPerSecond(1))
            I.AuraModel(1, GATE, 0, 0, 0, 13, Obs.CastSuccess, false) -- left form_a
            I.Settle(13)
            assert.are.equal(0, I.SwingPerSecond(1))
            obs(Obs.Usable, 14, SPENDER_C, 0, 1)
            obs(Obs.Usable, 14, SPENDER_C, 1, 0) -- the flip pins at spender_c's 10 with a step of 0
            I.Fold(14, false)
            local r = VS.Power(fs.RAGE, 14)
            assert.are.same({ 10, 10, 10 }, { r.est, r.lo, r.hi })
            obs(Obs.Usable, 16, SPENDER_C, 0, 1)
            obs(Obs.Usable, 16, SPENDER_C, 1, 0) -- a second measuring pin: nothing to calibrate against
            I.Fold(16, false)
            assert.are.same({ 1, 0 }, { I.res.scale[1], VS.Regen(fs.RAGE, 16).est })
        end)

        it("allocates nothing over 1000 swings and casts in and out of the aura", function()
            gated("form_a")
            local t = 10
            local bytes = alloc.bytes(function(i)
                t = t + 1
                if i % 2 == 0 then
                    I.AuraModel(1, GATE, t, t + 1.5, 1, t, Obs.CastSuccess, false)
                end
                obs(Obs.Swing, t + 0.5, 1, 2.5, 1)
                obs(Obs.CastSuccess, t + 0.6, SPENDER_C)
                I.Fold(t + 0.6, false)
                VS.Power(fs.RAGE, t + 0.7)
                I.SwingPerSecond(1)
            end, 1000)
            assert.are.equal(0, bytes)
        end)
    end)

    describe(
        "the in-game trace (2026-10-16, recorded on a Warrior's Bloodrage): a usability answer bounds the estimate",
        function()
            local REGEN_AURA_A = 3 -- the aura index
            local FIVE = 1 -- the abilities cost 5, 10 (spender_a), 10 (spender_c), 15 (spender_b): pins before caps
            local COST = { 5, 10, 10, 15 }

            before_each(function()
                local def = fs.def(fs.new(9))
                local five = { key = "five", spend = 5, spendType = "rage" }
                def.abilities = { five, def.abilities[1], def.abilities[3], def.abilities[2] }
                def.abilityIds = { { 1007 }, def.abilityIds[1], def.abilityIds[3], def.abilityIds[2] }
                def.abilitySlot = { 1, 1, 1, 1 }
                def.auras[REGEN_AURA_A] = { key = "regen_aura_a", id = 1021 }
                def.auraIds[REGEN_AURA_A] = { 1021 }
                def.resources[1].decay = 1.25
                def.resources[1].decayInterval = 1
                def.resources[1].auraRegen = { { aura = "regen_aura_a", interval = 1, value = 1, pausesDecay = true } }
                boot(def)
                I.Fold(50, false)
            end)

            -- The truth: 0; regen_aura_a at 50.3 (+10, then +1 a second); spender_a at 51.0 (-10).
            local function truth(t)
                if t < 50.3 then
                    return 0
                elseif t < 51 then
                    return 10
                end
                return math.floor(t - 50.3)
            end

            it(
                "keeps est on the modelled chain (= lo); a gain-explained flip bounds it at the cost, measuring nothing",
                function()
                    local t, raged, shouted = 50.1, false, false
                    while t < 59 do
                        if not raged and t >= 50.3 then
                            raged = true
                            I.Settle(50.3)
                            I.ResourceShift(1, 10, 50.3, Obs.CastSuccess) -- regen_aura_a's `now` gain
                            I.AuraModel(1, REGEN_AURA_A, 50.3, 60.3, 1, 50.3, 0)
                        end
                        if not shouted and t >= 51 then
                            shouted = true
                            I.Settle(51)
                            I.ResourceShift(1, -10, 51, Obs.CastSuccess) -- spender_a's spend
                        end
                        local v, cap = truth(t), 100
                        for a = 1, 4 do
                            if v >= COST[a] then
                                obs(Obs.Usable, t, a, 1, 0)
                            elseif a == FIVE and t < 51 then
                                obs(Obs.Usable, t, a, 0, 0) -- not usable for another reason: no rung
                            else
                                obs(Obs.Usable, t, a, 0, 1)
                                cap = math.min(cap, COST[a] - I.EPS)
                            end
                        end
                        I.Fold(t, false)
                        I.Settle(t)
                        local r = VS.Power(fs.RAGE, t)
                        -- the regen_aura_a flip bounds [10, the believed top]: hi stays the short answers' cap
                        local hi = cap
                        local got = ("%.2f est=%.2f lo=%.2f hi=%.2f"):format(t, r.est, r.lo, r.hi)
                        local want = ("%.2f est=%.2f lo=%.2f hi=%.2f"):format(t, v, v, hi)
                        assert.are.equal(want, got)
                        if t == 50.35 then
                            assert.is_false(I.res.pinValid[1]) -- the regen_aura_a flip is no regen measurement
                        end
                        t = t + 0.25
                    end
                    assert.are.equal(0, I.res.regen[1].last.modelled.t) -- no calibration from any flip
                end
            )

            it("clamps a wide flip's estimate down to its top when a tick took it past cost + step", function()
                local def = fs.def(fs.new(9))
                def.auras[REGEN_AURA_A] = { key = "regen_aura_a", id = 1021 }
                def.auraIds[REGEN_AURA_A] = { 1021 }
                def.resources[1].auraRegen = { { aura = "regen_aura_a", interval = 1, value = 10 } }
                boot(def)
                I.Fold(10, false)
                I.ResourceShift(1, 20, 10, Obs.CastSuccess)
                obs(Obs.Usable, 10, 2, 0, 1) -- spender_b (15) short: est 14.99
                I.Fold(10, false)
                within(15 - I.EPS, VS.Power(fs.RAGE, 10).est)
                I.AuraModel(1, REGEN_AURA_A, 10, 20, 1, 10, 0)
                I.Settle(11) -- a +10 tick, not our own gain: 24.99
                within(25 - I.EPS, VS.Power(fs.RAGE, 11).est)
                obs(Obs.Usable, 11, 2, 1, 0) -- usable: the swing-width flip [15, 15 + 9 x 1.1]
                I.Fold(11, false)
                local r = VS.Power(fs.RAGE, 11)
                within(15 + 9.9, r.est)
                within(15, r.lo)
                within(15 + 9.9, r.hi)
            end)
        end
    )

    describe("rage from damage taken (tank design §1.2: the paying entry's `taken`)", function()
        local WOUND, BLOCKED, BLOCK, DODGE, PARRY, MISS, HEAL = 1, 2, 3, 4, 5, 6, 7
        local calls

        local function taken(fn)
            local def = fs.def(fs.new(9))
            def.resources[1].taken = fn
            boot(def)
            I.Fold(10, false)
        end

        local function hit(t, kind, amount, level)
            obs(Obs.PlayerHit, t, kind, amount or 0, level or 20)
            I.Fold(t, false)
        end

        before_each(function()
            calls = {}
        end)

        it("gains on every kind but a heal, with the kind's name, the amount and the level", function()
            taken(function(kind, amount, level)
                calls[#calls + 1] = kind .. " " .. amount .. " " .. level
                return 2, 0.5
            end)
            hit(11, WOUND, 40, 12)
            hit(12, BLOCKED, 30)
            hit(13, BLOCK)
            hit(14, DODGE)
            hit(15, PARRY)
            hit(16, MISS)
            hit(17, HEAL, 50)
            assert.are.same({
                "WOUND 40 12",
                "BLOCKED 30 20",
                "BLOCK 0 20",
                "DODGE 0 20",
                "PARRY 0 20",
                "MISS 0 20",
            }, calls)
            local r = VS.Power(fs.RAGE, 17)
            assert.are.same({ 12, 9, 100, "modelled" }, { r.est, r.lo, r.hi, r.basis }) -- lo += 1.5 a hit; hi was 100
            assert.are.equal(12, I.res.gain[1]) -- our own gain: a flip it explains pins exactly
        end)

        it("moves lo by gain - width (never below 0) and hi by gain + width, clamped to the maximum", function()
            taken(function()
                return 3, 5
            end)
            obs(Obs.Usable, 10, 2, 0, 1) -- spender_b (15) short: hi 14.99
            I.Fold(10, false)
            hit(11, WOUND, 40)
            local r = VS.Power(fs.RAGE, 11)
            within(3, r.est)
            within(0, r.lo)
            within(15 - I.EPS + 8, r.hi)
            for k = 1, 40 do
                hit(11 + k, WOUND, 40)
            end
            r = VS.Power(fs.RAGE, 60)
            assert.are.same({ 100, 100 }, { r.est, r.hi })
        end)

        it("ignores a gain that is not a positive number, and a `taken` that raises counts as a now error", function()
            local answer
            taken(function()
                if answer == "raise" then
                    error("boom")
                end
                return answer
            end)
            for _, a in ipairs({ 0, -4, "5" }) do
                answer = a
                hit(11, WOUND, 40)
            end
            answer = "raise"
            hit(12, WOUND, 40)
            local r = VS.Power(fs.RAGE, 12)
            assert.are.same({ 0, "default" }, { r.est, r.basis })
            assert.are.equal(1, I.nowErrors)
        end)

        it("changes nothing for a slot without `taken`", function()
            boot(fs.def(fs.new(9)))
            hit(11, WOUND, 40)
            local r = VS.Power(fs.RAGE, 11)
            assert.are.same({ 0, "default" }, { r.est, r.basis })
        end)

        it("reads the belief at the hit's time through the `now` context (buff, talent, the resources)", function()
            taken(function()
                -- luacheck: ignore 113 (the `now` context's names)
                calls[#calls + 1] = talent.talent_a.rank .. " " .. rage.current .. " " .. combat
                return buff.spender_a.up and 4 or 1
            end)
            I.AuraModel(1, 1, 10, 20, 1, 10, 0) -- spender_a (aura 1) up from 10 to 20
            obs(Obs.CombatStart, 11)
            hit(12, WOUND, 40)
            I.SetTalentRank(1, 2)
            hit(25, WOUND, 40)
            assert.are.equal(5, VS.Power(fs.RAGE, 25).est)
            assert.are.same({ "0 0 11", "2 4 11" }, calls) -- the talent's rank, the rage before the hit, combat's start
        end)

        it(
            "explains a later flip by its gain: a bound at the cost, no swing calibration (the scale stays 1)",
            function()
                taken(function()
                    return 8
                end)
                obs(Obs.Usable, 10, 2, 0, 1) -- spender_b (15) short at 0
                I.Fold(10, false)
                hit(11, WOUND, 40)
                hit(12, WOUND, 40)
                obs(Obs.Usable, 12.1, 2, 1, 0) -- usable: the hits crossed 15
                I.Fold(12.1, false)
                local r = VS.Power(fs.RAGE, 12.1)
                assert.are.same({ 16, 15, "pinned" }, { r.est, r.lo, r.basis }) -- the flip proves 15, not the modelled 16
                assert.is_true(r.hi >= 16)
                assert.are.same({ 1, false }, { I.res.scale[1], I.res.pinValid[1] })
            end
        )

        it("keeps a hit's gain out of the swing calibration between two measuring pins (pinDelta)", function()
            taken(function()
                return 5
            end)
            obs(Obs.Swing, 10, 1, 2.6, 1) -- a landed swing: 9, and a speed to calibrate against
            obs(Obs.Read, 10.5, 1, 9, I.ReadOf.Resource) -- an exact read: a measuring pin
            I.Fold(10.5, false)
            hit(11, WOUND, 40)
            assert.are.equal(14, VS.Power(fs.RAGE, 12.5).est) -- the read below is explained by the hit's 5
            obs(Obs.Read, 12.5, 1, 14, I.ReadOf.Resource) -- 2 s on: no swing, so a swings-only regen of 0 (noise)
            I.Fold(12.5, false)
            -- with the 5 leaking into the measurement, 2.5/s against 9/2.6 would pull the scale to about 0.87
            assert.are.same({ 1, "observed" }, { I.res.scale[1], VS.Power(fs.RAGE, 12.5).basis })
        end)

        it("learns the rate: the last 10 s of gains / 10, in combat only, cleared at combat end", function()
            taken(function()
                return 2
            end)
            assert.are.equal(0, VS.TakenRate(fs.RAGE, 10))
            obs(Obs.CombatStart, 10)
            hit(11.5, WOUND, 40)
            hit(14.2, WOUND, 40)
            hit(18.9, WOUND, 40)
            within(0.6, VS.TakenRate(fs.RAGE, 19))
            within(0.4, VS.TakenRate(fs.RAGE, 21.5)) -- the second 11 left the window
            within(0.2, VS.TakenRate(fs.RAGE, 27.9))
            assert.are.equal(0, VS.TakenRate(fs.RAGE, 28)) -- ten quiet seconds
            hit(30, WOUND, 40)
            within(0.2, VS.TakenRate(fs.RAGE, 30))
            obs(Obs.CombatEnd, 31)
            I.Fold(31, false)
            assert.are.equal(0, VS.TakenRate(fs.RAGE, 31))
            obs(Obs.CombatStart, 32)
            I.Fold(32, false)
            assert.are.equal(0, VS.TakenRate(fs.RAGE, 32)) -- nothing kept from the last fight
            assert.are.equal(0, VS.TakenRate(ENERGY, 32)) -- an untracked type
        end)

        it("allocates nothing over 100 hits and rate reads", function()
            taken(function(kind, amount)
                return amount / 10, amount / 40
            end)
            obs(Obs.CombatStart, 10)
            I.Fold(10, false)
            local t = 10
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.7
                    hit(t, WOUND, 40)
                    VS.TakenRate(fs.RAGE, t)
                end, 100)
            )
        end)
    end)
end)

describe("the usability oracle (harness design §2: Rows' credits judged by the next usability answer)", function()
    local api, ctl, ns, VS, I, L, R, saved, rows
    local SPENDER_A, SPENDER_B = fs.SPENDER_A, fs.SPENDER_B -- the fake spec's spenders at 10 and 15
    local USABLE, SHORT = { true, false }, { false, true }

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        L, R = I.Log, I.res
        I.Build(fs.def(fs.new(9)), 1)
        ctl.damage[1], ctl.damage[2], ctl.damage[3], ctl.damage[4] = 36, 50, 24, 32
        ctl.now = 2
        VS.Start(api)
        rows = {}
        local GetInfo = ns.Facade.CombatLogGetCurrentEventInfo
        local sink = I.Events.CreateFrame("Frame")
        sink:SetScript("OnEvent", function()
            local t, ev, _, _, _, _, _, _, _, _, _, a12 = GetInfo()
            if rows and (ev == "SWING_DAMAGE" or ev == "SWING_MISSED") then -- nil: not recorded (the alloc case)
                rows[#rows + 1] = { ev, a12, t }
            end
        end)
        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    -- The client event at t, then a drain, then the rows it queued.
    local function at(t, event, ...)
        ctl.Tick(t)
        ctl.Fire(event, ...)
        ctl.Tick(t)
        fs.fold(ns, t)
        ctl.Tick(t)
    end
    local function answer(t, spell, ok)
        ctl.usable[spell] = ok and USABLE or SHORT
        at(t, "SPELL_UPDATE_USABLE")
    end
    -- In combat from 9.9 s at `est` (lo `lo`, hi `hi`); no spender has answered yet (no rung).
    local function setup(est, lo, hi)
        at(9.9, "PLAYER_REGEN_DISABLED")
        R.est0[1], R.lo0[1], R.hi0[1] = est, lo or est, hi or est
    end
    local function credit(t, amount, lag)
        at(t, "PLAYER_SWING", 2.2, 0)
        at(t + (lag or 0.47), "UNIT_COMBAT", "target", "WOUND", "", amount or 45, 1)
    end
    local function power(t)
        local p = VS.Power(fs.RAGE, t)
        return { p.lo, p.est, p.hi }
    end

    it("confirms a firm credit across a cost when the answer flips usable, and lowers its class's bar", function()
        setup(8)
        credit(10)
        assert.are.same({ 8 + 9 * 0.9, 17, 8 + 9 * 1.1 }, power(10.5))
        answer(10.52, SPENDER_A, true) -- before ORACLE_MIN after the outcome: no verdict yet
        assert.are.equal(0, L.oracle.judged)
        answer(10.6, SPENDER_A, true)
        assert.are.same({ 1, 1 }, { L.oracle.judged, L.oracle.confirmed })
        assert.are.equal(L.THETA / 1.1, L.theta[1]) -- main, exact, core band
    end)

    it("retracts a firm credit answered short: est, lo and hi back, the swing pending again", function()
        setup(8)
        credit(10)
        answer(10.6, SPENDER_A, false)
        assert.are.same({ 1, 1 }, { L.oracle.judged, L.oracle.retracted })
        assert.are.same({ 8, 8, 8 }, power(10.6)) -- lo never above its pre-credit value
        assert.are.equal(L.THETA * 1.5, L.theta[1])
        at(10.9, "UNIT_COMBAT", "target", "WOUND", "", 44, 1) -- in the tail: the re-held swing takes it
        assert.are.same({ { "SWING_DAMAGE", 45, 10 }, { "SWING_DAMAGE", 44, 10 } }, rows)
    end)

    it("closes a retracted swing past its window as SWING_MISSED (two rows for that swing, decision D9)", function()
        setup(8)
        credit(10, 45, 1.2)
        answer(11.6, SPENDER_A, false) -- 0.4 s after the outcome, 1.6 s after the swing
        assert.are.same({ { "SWING_DAMAGE", 45, 10 }, { "SWING_MISSED", "MISS", 10 } }, rows)
    end)

    it(
        "retracts after a short answer before ORACLE_MIN clamped the step: est, lo and hi back to 8, not below",
        function()
            setup(8)
            credit(10)
            answer(10.5, SPENDER_A, false) -- 0.03 s after the outcome: no verdict yet; the ladder clamps under 10
            answer(10.6, SPENDER_A, false)
            assert.are.equal(1, L.oracle.retracted)
            assert.are.same({ 8, 8, 8 }, power(10.6))
        end
    )

    it("retracts a credited crit with its swing: lo back at its pre-credit value", function()
        setup(2)
        R.swingCrit[1] = 4
        at(10, "PLAYER_SWING", 2.2, 0)
        at(10.47, "UNIT_COMBAT", "target", "WOUND", "CRITICAL", 90, 1)
        assert.are.same({ 2 + 9 * 0.9 + 4, 15, 2 + 9 * 1.1 + 4 }, power(10.5))
        answer(10.6, SPENDER_A, false)
        assert.are.equal(1, L.oracle.retracted)
        assert.are.same({ 2, 2, 2 }, power(10.6))
    end)

    it("rescues nothing for a flip our confirmed credit explains, and gives back the stale short's cut", function()
        setup(5)
        answer(9.95, SPENDER_A, false)
        L.theta[2] = 8 -- main, exact, tail: the 45 at 1.3 s is dropped
        credit(10, 45, 1.3)
        credit(11, 45, 0.47) -- ours, credited: 5 + 9 crosses 10
        answer(11.5, SPENDER_A, false) -- 0.03 s after the outcome: the ladder clamps under 10, the cut kept
        assert.are.same({ 9.99, 9.99, 9.99 }, power(11.5))
        answer(11.67, SPENDER_A, true) -- at least 10: the short was the client's from before the credit
        assert.are.same({ 1, 0 }, { L.oracle.confirmed, L.oracle.rescued })
        assert.are.same({ 5 + 9 * 0.9, 14, 5 + 9 * 1.1 }, power(11.67))
    end)

    it("gives a crit credit's cut back: its landing poll's short answer was the client's from before it", function()
        setup(5)
        R.swingCrit[1] = 20
        answer(9.95, SPENDER_A, false)
        at(10, "PLAYER_SWING", 2.2, 0)
        at(10.47, "UNIT_COMBAT", "target", "WOUND", "CRITICAL", 90, 1) -- 5 + 9 + 20; Rows polls usability: short
        assert.are.same({ 9.99, 9.99, 9.99 }, power(10.5))
        answer(10.6, SPENDER_A, true)
        assert.are.same({ 5 + 9 * 0.9 + 20, 34, 5 + 9 * 1.1 + 20 }, power(10.6))
    end)

    it("bounds a flip a credit explains as a rung, not the pin at the cost plus one white step", function()
        setup(5)
        R.swingCrit[1] = 20
        answer(9.95, SPENDER_A, false)
        at(10, "PLAYER_SWING", 2.2, 0)
        ctl.usable[SPENDER_A] = USABLE -- the client already shows the swing's rage at its wound
        at(10.47, "UNIT_COMBAT", "target", "WOUND", "CRITICAL", 90, 1) -- Rows' landing poll: the flip
        assert.are.same({ 5 + 9 * 0.9 + 20, 34, 5 + 9 * 1.1 + 20 }, power(10.5)) -- not [10, 10 + 9.9]
    end)

    it(
        "gives a young short's cut back only on a usable answer at its cost or dearer (Arms seed 6 at 81.4 s)",
        function()
            -- the loop: a white crit credited 21 -> 49.8 (truth 52.7), then Mortal Strike's short answer 0.04 s later (the
            -- client still at 24) cut it to 29.99 for good; its usable answer 0.06 s later now gives the cut back
            setup(8)
            credit(10) -- 8 + 9 crosses spender_a (10) and spender_b (15)
            answer(10.5, SPENDER_B, false) -- young: cut (the floor holds whether the credit is stale or false)
            assert.are.same({ 14.99, 14.99, 14.99 }, power(10.5))
            answer(10.6, SPENDER_A, true) -- at least 10 says nothing of 15: the cut stands
            assert.are.same({ 14.99, 14.99, 14.99 }, power(10.6))
            answer(10.65, SPENDER_B, true)
            assert.are.same({ 8 + 9 * 0.9, 17, 8 + 9 * 1.1 }, power(10.65))
        end
    )

    it("keeps a young short's cut after one of our spends, or past the verdict window", function()
        setup(8)
        credit(10)
        answer(10.5, SPENDER_B, false)
        at(10.55, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", SPENDER_A) -- 10 paid: 4.99
        answer(10.6, SPENDER_B, true) -- not from the cut state: a plain rung
        assert.are.equal(15, power(10.6)[1])
        R.est0[1], R.lo0[1], R.hi0[1] = 8, 8, 8
        credit(20)
        answer(20.5, SPENDER_B, false)
        answer(21.2, SPENDER_B, true) -- 0.73 s after the outcome: past ORACLE_MAX
        assert.are.equal(15, power(21.2)[1])
    end)

    it("labels a soft credit (only its estimate crossed) at half weight and retracts nothing", function()
        setup(8, 0, 8)
        credit(10)
        answer(10.6, SPENDER_A, false)
        assert.are.same({ 1, 0 }, { L.oracle.soft, L.oracle.retracted })
        assert.are.equal(L.THETA * 1.22, L.theta[1])
        assert.are.equal(8.1, power(10.6)[1]) -- the credit's floor stays; the ladder clamped est and hi under 10
    end)

    it("gives no verdict when one of our casts spent from the slot between the outcome and the answer", function()
        setup(8)
        credit(10)
        at(10.55, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", SPENDER_A)
        answer(10.6, SPENDER_A, false)
        assert.are.equal(0, L.oracle.judged)
    end)

    it(
        "rescues a dropped wound for a flip nothing explains: its swing paid, its row out; without one, today's pin",
        function()
            setup(5)
            answer(9.95, SPENDER_A, false)
            L.theta[2] = 8 -- main, exact, tail: the 45 at 1.3 s (LR 7.2) is dropped
            credit(10, 45, 1.3)
            assert.are.same({ 0, 0 }, { #rows, L.oracle.rescued })
            answer(11.45, SPENDER_A, true)
            assert.are.same({ 1, 0 }, { L.oracle.rescued, L.oracle.rescuedLate })
            assert.are.same({ { "SWING_DAMAGE", 45, 10 } }, rows)
            local p = power(11.45) -- 5 + 9, then the explained flip bounds it: at least the cost
            assert.are.same({ 10, 14 }, { p[1], p[2] })
            assert.is_true(p[3] >= 14)
            answer(12, SPENDER_A, false)
            R.est0[1], R.lo0[1], R.hi0[1] = 5, 5, 5
            answer(12.5, SPENDER_A, true) -- nothing dropped: the swing-paid pin [10, 10 + a step)
            assert.are.same({ 10, 10, 10 + 9 * 1.1 }, power(12.5))
        end
    )

    it("keeps lo a floor when a rescued swing's step is too big (the Arms seed 4 trace at 49 s)", function()
        -- believed 9.5 (truth 9.2, under spender_a's 10); the dropped wound's swing is modelled at 9, the game gave 8:
        -- truth 17.2. The flip it explains proves only "at least 10" (in game: 30 + 17.7 believed, 28.8 + 16.2 true)
        setup(9.5, 9, 9.99)
        answer(9.95, SPENDER_A, false)
        L.theta[2] = 8 -- main, exact, tail: the 45 at 1.3 s is dropped
        credit(10, 45, 1.3)
        answer(11.45, SPENDER_A, true)
        assert.are.equal(1, L.oracle.rescued)
        local p = power(11.45)
        assert.is_true(p[1] <= 17.2 and p[1] >= 10, ("lo %.2f, truth 17.2"):format(p[1]))
        assert.are.equal(18.5, p[2]) -- the estimate keeps the modelled step
    end)

    it("allocates nothing over a retraction past its window, a soft verdict and a late rescue", function()
        setup(8)
        rows = nil
        local o, b = L.oracle, 0
        local function cycle()
            b = b + 20
            answer(b - 1, SPENDER_A, false) -- the last cycle's usable rung forgotten
            R.est0[1], R.lo0[1], R.hi0[1] = 8, 8, 8
            for k = 1, #L.theta do -- every class's bar back at THETA: each cycle credits as the first
                L.theta[k] = L.THETA
            end
            credit(b, 45, 1.2)
            answer(b + 1.6, SPENDER_A, false) -- retracted 0.4 s after the outcome, past the swing's window: MISS
            R.est0[1], R.lo0[1], R.hi0[1] = 8, 0, 8
            credit(b + 4)
            answer(b + 4.6, SPENDER_A, false) -- soft: only the estimate crossed
            R.est0[1], R.lo0[1], R.hi0[1] = 5, 5, 5
            answer(b + 7.95, SPENDER_A, false)
            L.theta[2] = math.huge -- main, exact, tail: the 45 at 1.3 s is dropped
            credit(b + 8, 45, 1.3)
            answer(b + 9.6, SPENDER_A, true) -- after the swing's window closed: rescued late (rage only)
        end
        local before = { o.retracted, o.soft, o.rescuedLate }
        cycle()
        assert.are.same({ before[1] + 1, before[2] + 1, before[3] + 1 }, { o.retracted, o.soft, o.rescuedLate })
        assert.are.equal(0, alloc.bytes(cycle, 100))
        assert.are.same({ before[1] + 302, before[2] + 302, before[3] + 302 }, { o.retracted, o.soft, o.rescuedLate })
    end)

    it("caps a class's bar at THETA_MAX after ten negatives and floors it at THETA_MIN after positives", function()
        setup(8)
        for k = 0, 9 do
            credit(10 + 3 * k)
            answer(10.6 + 3 * k, SPENDER_A, false)
        end
        assert.are.equal(L.THETA_MAX, L.theta[1])
        for k = 10, 39 do
            R.est0[1], R.lo0[1], R.hi0[1] = 8, 8, 8
            credit(10 + 3 * k)
            answer(10.6 + 3 * k, SPENDER_A, true)
            answer(11 + 3 * k, SPENDER_A, false)
        end
        assert.are.equal(L.THETA_MIN, L.theta[1])
    end)
end)
