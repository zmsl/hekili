-- tests/Game/State/facts_spec.lua: the polls and the smaller families (spec §4.3, §6.5-§6.9): the usability ladder
-- poll, known ranks, talents, totems, the target's cast, enemies, health, stats.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("facts and polls", function()
    local VS, I, S, Obs, ctl

    before_each(function()
        local api
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    local function drain(t)
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t, false)
        I.Settle(t)
    end

    it("asks the highest known rank, and skips a secret usability answer", function()
        ctl.known[fs.SPENDER_C], ctl.known[fs.SPENDER_C_R2] = true, true
        ctl.Fire("SPELLS_CHANGED")
        assert.are.equal(fs.SPENDER_C_R2, I.ab.qid[3])
        ctl.usable[fs.SPENDER_C_R2] = { true, false }
        ctl.usable[fs.SPENDER_B] = { fake.SECRET, false }
        drain(5)
        local r = VS.Power(fs.RAGE, 5)
        assert.are.equal(10, r.lo) -- spender_c's rung; heroic strike's secret answer is no news
    end)

    it("takes no rung from an ability with a second power cost", function()
        ctl.costs[fs.SPENDER_C] = { { type = 1, cost = 10 }, { type = 4, cost = 5, minCost = 1 } } -- rage + combo points
        ctl.known[fs.SPENDER_C] = true
        ctl.Fire("SPELLS_CHANGED")
        assert.are.same({ true, false }, { I.ab.multiCost[3], I.ab.multiCost[1] })
        ctl.usable[fs.SPENDER_C] = { false, true } -- "short": of rage or of the combo point?
        drain(5)
        assert.are.equal(100, VS.Power(fs.RAGE, 5).hi) -- no rung
        ctl.usable[fs.SPENDER_C] = { true, false }
        drain(6)
        assert.are.equal(0, VS.Power(fs.RAGE, 6).lo) -- nor from its usable answer
    end)

    it("reads the second-cost flag at combat end after a build in combat", function()
        ctl.costs[fs.SPENDER_C] = { { type = 1, cost = 10 }, { type = 4, cost = 5, minCost = 1 } }
        ctl.known[fs.SPENDER_C] = true
        ctl.Fire("PLAYER_REGEN_DISABLED")
        I.Build(fs.def(fs.new(9)), 1) -- a /reload in combat
        assert.is_false(I.ab.multiCost[3])
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.same({ true, 10 }, { I.ab.multiCost[3], I.ab.readCost[3] })
    end)

    it("prices a fraction cost from its pool's base, which a plain cost read out of combat teaches", function()
        local h = fs.new(9)
        h.Class.abilities.spender_c.spend = 0.055 -- a percent-of-base cost
        local def = fs.def(h)
        def.resources[1].base = 200 -- the pack's fallback
        I.Build(def, 1)
        ctl.known[fs.SPENDER_C] = true
        assert.are.same({ 11, 200 }, { I.CostOf(3), VS.BasePower(fs.RAGE) }) -- floor(0.055 x 200), before any read
        ctl.costs[fs.SPENDER_C] = { { type = 1, cost = 12 } }
        ctl.Fire("SPELLS_CHANGED")
        assert.are.same({ 12, 219 }, { I.CostOf(3), VS.BasePower(fs.RAGE) }) -- the least whole base pricing it 12
        ctl.Fire("SPELLS_CHANGED") -- a read the base prices keeps it
        assert.are.equal(219, VS.BasePower(fs.RAGE))
        ctl.costs[fs.SPENDER_C] = { { type = 1, cost = 14 } }
        ctl.Fire("PLAYER_LEVEL_UP", 21) -- a new level's base
        assert.are.same({ 14, 255 }, { I.CostOf(3), VS.BasePower(fs.RAGE) })
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.costs[fs.SPENDER_C] = { { type = 1, cost = 20 } }
        ctl.Fire("SPELLS_CHANGED") -- no cost read in combat
        assert.are.equal(255, VS.BasePower(fs.RAGE))
        def.resources[1].base = nil -- no base: a fraction of the maximum, as Hekili prices it
        I.Build(def, 1)
        assert.are.same({ 5.5, nil }, { I.CostOf(3), VS.BasePower(fs.RAGE) })
    end)

    it("learns the base after the talent walk, from the read with the largest fraction", function()
        local h = fs.new(9)
        local function scaled() -- a talent-scaled percent-of-base cost, read in the belief's context
            return 0.5 * (1 - 0.1 * talent.talent_a.rank)
        end
        local a, c = h.Class.abilities.spender_a, h.Class.abilities.spender_c
        a.spend, a.declaredSpend = scaled, scaled
        c.spend = 0.03
        local def = fs.def(h)
        def.resources[1].base = 200
        I.Build(def, 1)
        -- the true base 310: at rank 2 spender_a costs floor(0.4 x 310) = 124, spender_c floor(0.03 x 310) = 9
        ctl.known[fs.SPENDER_A], ctl.known[fs.SPENDER_C] = true, true
        ctl.costs[fs.SPENDER_A] = { { type = 1, cost = 124 } }
        ctl.costs[fs.SPENDER_C] = { { type = 1, cost = 9 } }
        ctl.traits = { config = 1, trees = { 7 }, nodeIDs = { 70 }, nodes = {}, defs = { [700] = 1011 } }
        ctl.traits.nodes[70] = { entryIDs = { 700 }, activeRank = 2 } -- first known in the same SPELLS_CHANGED
        ctl.Fire("SPELLS_CHANGED")
        assert.are.same({ 2, 310 }, { VS.Talent(1011), VS.BasePower(fs.RAGE) })
        assert.are.same({ 124, 9 }, { I.CostOf(1), I.CostOf(3) })
    end)

    it("walks the talent tree into ranks by registered spell ID, and defers a walk in combat", function()
        ctl.traits = { config = 1, trees = { 7 }, nodeIDs = { 70 }, nodes = {}, defs = { [700] = 1011 } }
        ctl.traits.nodes[70] = { entryIDs = { 700 }, activeRank = 2 }
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.are.equal(2, VS.Talent(1011))
        local gen = VS.TalentGen()
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.traits.nodes[70].activeRank = 3
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.are.equal(2, VS.Talent(1011))
        ctl.Fire("PLAYER_REGEN_ENABLED")
        drain(6)
        assert.are.same({ 3, gen + 1 }, { VS.Talent(1011), VS.TalentGen() })
        assert.are.equal(0, VS.Talent(99999))
        assert.are.equal("unused", S.status["talent walk aliases"])
        assert.is_truthy(VS.Snapshot():find("talent walk unmatched: 0\n", 1, true))
    end)

    it("names the definition spells the walk could not match", function()
        local defs = { [700] = 1011, [710] = 54321, [720] = 65432 }
        ctl.traits = { config = 1, trees = { 7 }, nodeIDs = { 70, 71, 72 }, nodes = {}, defs = defs }
        ctl.traits.nodes[70] = { entryIDs = { 700 }, activeRank = 2 }
        ctl.traits.nodes[71] = { entryIDs = { 710 }, activeRank = 1 }
        ctl.traits.nodes[72] = { entryIDs = { 720 }, activeRank = 0 } -- untaken: not listed
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.are.equal(2, VS.Talent(1011))
        assert.is_truthy(VS.Snapshot():find("talent walk unmatched: 1 [54321]\n", 1, true))
        I.TALENT_UNMATCHED = 1 -- overflow: the true count, only `cap` IDs
        ctl.traits.nodes[72].activeRank = 1
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.is_truthy(VS.Snapshot():find("talent walk unmatched: 2 [54321]\n", 1, true))
    end)

    it("reads totems out of combat and takes an update in combat with no cast as a destruction", function()
        ctl.totems[1] = { name = "Totem", start = 2, duration = 30, icon = 55, spell = 1234 }
        drain(5)
        assert.are.same({ 1234, "Totem", 55, 2, 30 }, { VS.TotemFacts(1) })
        assert.are.equal(32, VS.Totem(1, 5).est)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.now = 8
        ctl.Fire("PLAYER_TOTEM_UPDATE", 1)
        drain(8)
        assert.is_nil(VS.Totem(1, 8))
        assert.is_nil(VS.TotemFacts(1))
    end)

    it("times the target's cast by castBarID", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_START", "target", fake.SECRET, fake.SECRET, 77)
        drain(10)
        assert.are.same({ false, 77, 10, -1 }, { VS.TargetCastFacts() })
        assert.are.equal(10 + I.TARGET_CAST_DEFAULT, VS.TargetCast(10.5).est)
        ctl.Fire("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
        drain(10.6)
        assert.are.equal(1, select(4, VS.TargetCastFacts()))
        ctl.Fire("UNIT_SPELLCAST_INTERRUPTED", "target", fake.SECRET, fake.SECRET, "Player-1", 77)
        drain(11)
        assert.is_nil(VS.TargetCastFacts())
        assert.is_nil(VS.TargetCast(11))
    end)

    it("counts live attackable plates, default 1 without any", function()
        drain(2)
        assert.are.equal(1, VS.Count.Enemies(2).est)
        ctl.exists.nameplate1, ctl.exists.nameplate2, ctl.exists.nameplate3 = true, true, true
        ctl.dead.nameplate3 = true
        ctl.inRange.nameplate1 = true
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        drain(3)
        local e = VS.Count.Enemies(3)
        assert.are.same({ 2, "observed" }, { e.est, e.basis })
        assert.are.equal(1, VS.Count.InRange(fs.SPENDER_C, 3))
    end)

    it(
        "brackets the target's distance from the abilities' own ranges, keeping the last through secret reads",
        function()
            ctl.known[fs.SPENDER_A], ctl.known[fs.SPENDER_C] = true, true
            ctl.ranges[fs.SPENDER_A], ctl.ranges[fs.SPENDER_C] = { 0, 5 }, { 8, 35 } -- a melee strike, a band
            ctl.Fire("SPELLS_CHANGED")
            assert.are.same({ 0, 5, 8, 35 }, { I.ab.rMin[1], I.ab.rMax[1], I.ab.rMin[3], I.ab.rMax[3] })
            assert.are.equal(0, I.ab.rMax[2]) -- on the next swing: never asked
            ctl.distance.target = fake.SECRET
            ctl.Fire("PLAYER_TARGET_CHANGED")
            drain(2)
            assert.are.equal("unknown", VS.TargetRange().basis) -- a target, no plain answer yet
            local function bracket(d, t)
                ctl.distance.target = d
                drain(t)
                local r = VS.TargetRange()
                return { r.lo, r.hi, r.est, r.basis }
            end
            assert.are.same({ 0, 5, 2.5, "observed" }, bracket(2, 3)) -- in melee, so nearer than the band
            assert.are.same({ 8, 35, 21.5, "observed" }, bracket(20, 4))
            -- past the strike (strictly: lo 5 is beyond 5 yd), either side of the band: no upper bound, est up to 40
            assert.are.same({ 5, math.huge, 22.5, "observed" }, bracket(6, 5))
            assert.are.same({ 5, math.huge, 22.5, "observed" }, bracket(40, 6))
            assert.are.same({ 5, math.huge, 22.5, "observed" }, bracket(fake.SECRET, 7)) -- secret: the last bracket stays
            ctl.Fire("PLAYER_TARGET_CHANGED")
            drain(8)
            assert.are.equal("unknown", VS.TargetRange().basis) -- a swap forgets it until the next plain answer
            assert.are.same({ 0, 5, 2.5, "observed" }, bracket(3, 9))
            ctl.ranges[fs.SPENDER_C] = { 0, 35 } -- the client now answers the band in melee too (the resolved 8 stays)
            assert.are.same({ 5, 5, 5, "observed" }, bracket(3, 10)) -- lo 8 over hi 5: the upper bound wins
        end
    )

    it("reads the player's health when plain and caches the stats out of combat", function()
        ctl.health, ctl.healthMax = 500, 1000
        drain(2)
        assert.are.equal(0.5, VS.Health("player", 2).est)
        assert.are.equal(1000, VS.HealthMax("player"))
        assert.are.same({ 1, 100 }, { VS.Health("target", 2).est, VS.HealthMax("target") })
        assert.are.equal(30, VS.TTD("target", 2).est)
        assert.are.same({ 0, 0, 0, 0, 0, 0, 0 }, { VS.Stat("UnitStat", 1) })
        assert.are.same({ 0, 0, 0, 0, 0, 0, 0 }, { VS.Stat("NoSuchStat") })
    end)

    it("reads the player's health as full while the client keeps it secret, the plain value again after", function()
        ctl.health, ctl.healthMax = 300, 1000
        drain(2)
        assert.are.equal(0.3, VS.Health("player", 2).est) -- out of combat, plain: honoured
        ctl.Fire("PLAYER_REGEN_DISABLED") -- the pull: the plain read from before it is forgotten at once
        ctl.Tick(2.5)
        I.Fold(2.5, false) -- before the next poll
        local h = VS.Health("player", 2.5)
        assert.are.same({ 1, "default", 0 }, { h.est, h.basis, h.conf })
        ctl.unitHealth.player = fake.SECRET -- secret in combat
        drain(3)
        h = VS.Health("player", 3)
        assert.are.same({ 1, "default", 0 }, { h.est, h.basis, h.conf })
        drain(4)
        assert.are.equal(1, VS.Health("player", 4).est) -- every secret poll the same: no flicker
        ctl.unitHealth.player = 400
        drain(5)
        assert.are.equal(0.4, VS.Health("player", 5).est)
    end)
end)
