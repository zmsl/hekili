-- VirtualState/spec/resources_spec.lua: the resources family (spec §6.1). Golden scenario 2 (TDF
-- tests/model/belief_spec.lua:197, 568): the cost ladder bounds a resource, and regen is measured between two pins
-- net of our own spends.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")
local alloc = require("VirtualState.spec.helpers.alloc")

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
                resources = { { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = 100, regen = 10 } },
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

        it("pins an exact plain read and widens a late one by the regen spread", function()
            obs(Obs.Read, 20, 1, 55, I.ReadOf.Resource)
            I.Fold(20, false)
            local e = VS.Power(ENERGY, 20)
            assert.are.same({ 55, 55, 55, "observed" }, { e.est, e.lo, e.hi, e.basis })
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

        it("pays no swing step while an on-next-swing strike is queued", function()
            obs(Obs.Queued, 4, 2, 1) -- heroic_strike (ability 2) queued
            obs(Obs.Swing, 5, 1, 2.6, 1)
            I.Fold(5, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 5).est)
        end)

        it("alternates pinned (the ladder) and modelled (a swing, a cast) and keeps lo at or above what was seen", function()
            obs(Obs.Usable, 5, 3, 1, 0) -- rend (10) usable
            obs(Obs.Usable, 5, 2, 0, 1) -- heroic strike (15) short
            I.Fold(5, false)
            local r = VS.Power(fs.RAGE, 5)
            assert.are.equal("pinned", r.basis)
            assert.is_true(r.lo >= 10 and r.hi < 15)
            I.ResourceShift(1, -10, 6, Obs.CastSuccess)
            r = VS.Power(fs.RAGE, 6)
            assert.are.equal("modelled", r.basis)
            assert.is_true(r.hi - r.lo <= 15)
        end)

        it("keeps basis default at rest when a rung bounds the interval without moving the estimate", function()
            obs(Obs.Usable, 5, 1, 0, 1) -- battle shout (10) short at 0 rage, out of combat
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

        it("pays nothing for an off-hand swing when only the main hand pays", function()
            obs(Obs.Swing, 5, 2, 1.8, 1)
            I.Fold(5, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 5).est)
        end)

        it("pays each hand its own value when both hands pay it, and calibrates against their sum", function()
            local def = fs.def(fs.new(9))
            def.resources[1].swingOff = 4.5
            boot(def)
            obs(Obs.Swing, 5, 1, 2.6, 1)
            obs(Obs.Swing, 5.5, 2, 1.8, 1)
            I.Fold(5.5, false)
            assert.are.equal(13.5, VS.Power(fs.RAGE, 6).est)
            within(9 / 2.6 + 4.5 / 1.8, I.SwingPerSecond(1))
            within(9 / 2.6 + 4.5 / 1.8, VS.Regen(fs.RAGE, 6).est)
            obs(Obs.Queued, 6, 2, 1) -- a queued strike takes the main hand's swing, not the off hand's
            obs(Obs.Swing, 7.3, 2, 1.8, 1)
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
end)
