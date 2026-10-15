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

        it("answers an untracked power type with the unknown record", function()
            local u = VS.Power(99, 1)
            assert.are.same({ 0, "unknown" }, { u.conf, u.basis })
        end)
    end)

    describe("aura-gated regen (rage, Bloodrage: 1 a second while its aura is up)", function()
        local BLOODRAGE = 3 -- the aura index

        before_each(function()
            local def = fs.def(fs.new(9))
            def.auras[BLOODRAGE] = { key = "bloodrage", id = 29131 }
            def.auraIds[BLOODRAGE] = { 29131 }
            def.resources[1].auraRegen = {
                { aura = "bloodrage", interval = 1, value = 1 },
                { aura = "not_tracked", interval = 1, value = 5 }, -- no such aura: ignored
            }
            boot(def)
            I.Fold(10, false) -- the clock starts at 10
        end)

        it("adds value at each interval after the aura's application while it is believed up", function()
            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
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
            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0)
            I.Settle(12.5)
            I.AuraModel(1, BLOODRAGE, 0, 0, 0, 12.5, 0) -- gone at 12.5 (expiry 0: down)
            I.Settle(20)
            assert.are.equal(2, VS.Power(fs.RAGE, 20).est)
        end)

        it("allocates nothing advancing or projecting through an entry", function()
            I.AuraModel(1, BLOODRAGE, 10, 1e9, 1, 10, 0)
            local t = 10
            local bytes = alloc.bytes(function()
                t = t + 0.1
                I.Settle(t)
                VS.Power(fs.RAGE, t + 0.5)
            end, 10000)
            assert.are.equal(0, bytes)
        end)
    end)
end)
