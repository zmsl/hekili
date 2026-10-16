-- tests/Virtual/State/resources_spec.lua: the resources family (spec §6.1). Golden scenario 2 (TDF
-- tests/model/belief_spec.lua:197, 568): the cost ladder bounds a resource, and regen is measured between two pins
-- net of our own spends.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local fs = require("Virtual.State.helpers.fake_spec")
local alloc = require("Virtual.State.helpers.alloc")

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

        it("pays no swing step while an on-next-swing strike is queued", function()
            obs(Obs.Queued, 4, 2, 1) -- heroic_strike (ability 2) queued
            obs(Obs.Swing, 5, 1, 2.6, 1)
            I.Fold(5, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 5).est)
        end)

        it(
            "alternates pinned (the ladder) and modelled (a swing, a cast) and keeps lo at or above what was seen",
            function()
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
            end
        )

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

        it("pauses the out-of-combat decay while an aura-gated entry's aura is up, resumes after it expires", function()
            local def = fs.def(fs.new(9))
            def.auras[BLOODRAGE] = { key = "bloodrage", id = 29131 }
            def.auraIds[BLOODRAGE] = { 29131 }
            def.resources[1].decay = 2
            def.resources[1].auraRegen = { { aura = "bloodrage", interval = 1, value = 1 } }
            boot(def)
            I.Fold(10, false)
            I.ResourceShift(1, 20, 10, Obs.CastSuccess) -- est 20, out of combat
            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
            I.Settle(15)
            assert.are.equal(25, VS.Power(fs.RAGE, 15).est) -- 5 ticks, no decay
            I.Settle(22)
            assert.are.equal(26, VS.Power(fs.RAGE, 22).est) -- 5 more ticks, then 2 s x 2/s after the expiry
        end)

        it("lands the tick at the expiry: a 10 s aura ticking 1 a second lands 10", function()
            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
            assert.are.equal(5, VS.Power(fs.RAGE, 15).est) -- (10, 15]: 11 to 15
            assert.are.equal(10, VS.Power(fs.RAGE, 20).est) -- (10, 20]: 11 to 20, the expiry's tick too
            assert.are.equal(10, VS.Power(fs.RAGE, 30).est) -- (10, 30]: nothing after it
        end)

        it("leaves decay at the full rate when the tick aura is down or already expired", function()
            local def = fs.def(fs.new(9))
            def.auras[BLOODRAGE] = { key = "bloodrage", id = 29131 }
            def.auraIds[BLOODRAGE] = { 29131 }
            def.resources[1].decay = 2
            def.resources[1].auraRegen = { { aura = "bloodrage", interval = 1, value = 1 } }
            boot(def)
            I.Fold(10, false)
            I.ResourceShift(1, 50, 10, Obs.CastSuccess) -- est 50, out of combat, aura never applied
            I.Settle(15)
            assert.are.equal(40, VS.Power(fs.RAGE, 15).est) -- 2/s x 5
            I.AuraModel(1, BLOODRAGE, 5, 12, 1, 15, 0) -- applied at 5, expired at 12, before this advance
            I.Settle(20)
            assert.are.equal(30, VS.Power(fs.RAGE, 20).est) -- still 2/s x 5
        end)

        it("credits a plain periodic entry only in combat, from the combat start, and only with its talent", function()
            local def = fs.def(fs.new(9))
            def.resources[1].auraRegen = { { talent = "improved_rend", interval = 3, value = 1 } }
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

    describe("stepped decay (rage: 1.25 lost at the start of each 1 s window out of combat)", function()
        local BLOODRAGE = 3 -- the aura index

        before_each(function()
            local def = fs.def(fs.new(9))
            def.auras[BLOODRAGE] = { key = "bloodrage", id = 29131 }
            def.auraIds[BLOODRAGE] = { 29131 }
            def.resources[1].decay = 1.25
            def.resources[1].decayInterval = function() -- a function, as a class file's meta table declares it
                return 1
            end
            def.resources[1].auraRegen = { { aura = "bloodrage", interval = 1, value = 1 } }
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

        it("lands Bloodrage's tenth tick at its expiry, then the first quantum at once: 10 - 1.25", function()
            S.Direct(Obs.CombatEnd, 5)
            I.Fold(5, false) -- at rest (0): no quantum
            I.Settle(10)
            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
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
            I.AuraModel(1, BLOODRAGE, 13, 23, 1, 12.5, 0) -- applied at 13, expires at 23
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

    describe("a swing entry gated on a player aura (bear rage: swings pay only in Bear Form)", function()
        local BEAR, REND = 3, 3 -- the aura index; fs.def's ability index of Rend (10 rage)

        local function gated(aura)
            local def = fs.def(fs.new(9))
            def.auras[BEAR] = { key = "bear_form", id = 5487 }
            def.auraIds[BEAR] = { 5487 }
            def.resources[1].swingAura = aura
            boot(def)
            I.Fold(10, false)
        end

        local function swing(t)
            obs(Obs.Swing, t, 1, 2.5, 1)
            I.Fold(t, false)
            return VS.Power(fs.RAGE, t).est
        end

        it("pays only while the aura is believed up: never applied, applied (as a `now` writes it), expired", function()
            gated("bear_form")
            assert.are.equal(0, swing(11))
            I.AuraModel(1, BEAR, 12, 30, 1, 12, Obs.CastSuccess, false) -- the shift's applyBuff
            assert.are.equal(9, swing(13.5))
            assert.are.equal(18, swing(16))
            assert.are.equal(18, swing(31)) -- past the believed expiry
        end)

        it("pays nothing when the gate names an untracked aura, and as before without a gate", function()
            gated("dire_bear_test")
            I.AuraModel(1, BEAR, 12, 30, 1, 12, Obs.CastSuccess, false)
            assert.are.equal(0, swing(13.5))
            gated(nil)
            assert.are.equal(9, swing(11))
        end)

        it("out of the aura: no swing rate to calibrate against, and a zero-width pin on the ladder", function()
            gated("bear_form")
            swing(11) -- a speed to divide by
            I.AuraModel(1, BEAR, 12, 30, 1, 12, Obs.CastSuccess, false)
            I.Settle(12)
            within(9 / 2.5, I.SwingPerSecond(1))
            I.AuraModel(1, BEAR, 0, 0, 0, 13, Obs.CastSuccess, false) -- left Bear Form
            I.Settle(13)
            assert.are.equal(0, I.SwingPerSecond(1))
            obs(Obs.Usable, 14, REND, 0, 1)
            obs(Obs.Usable, 14, REND, 1, 0) -- the flip pins at Rend's 10 with a step of 0
            I.Fold(14, false)
            local r = VS.Power(fs.RAGE, 14)
            assert.are.same({ 10, 10, 10 }, { r.est, r.lo, r.hi })
            obs(Obs.Usable, 16, REND, 0, 1)
            obs(Obs.Usable, 16, REND, 1, 0) -- a second measuring pin: nothing to calibrate against
            I.Fold(16, false)
            assert.are.same({ 1, 0 }, { I.res.scale[1], VS.Regen(fs.RAGE, 16).est })
        end)

        it("allocates nothing over 1000 swings and casts in and out of the aura", function()
            gated("bear_form")
            local t = 10
            local bytes = alloc.bytes(function(i)
                t = t + 1
                if i % 2 == 0 then
                    I.AuraModel(1, BEAR, t, t + 1.5, 1, t, Obs.CastSuccess, false)
                end
                obs(Obs.Swing, t + 0.5, 1, 2.5, 1)
                obs(Obs.CastSuccess, t + 0.6, REND)
                I.Fold(t + 0.6, false)
                VS.Power(fs.RAGE, t + 0.7)
                I.SwingPerSecond(1)
            end, 1000)
            assert.are.equal(0, bytes)
        end)
    end)
end)
