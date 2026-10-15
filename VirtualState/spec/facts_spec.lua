-- VirtualState/spec/facts_spec.lua: the polls and the smaller families (spec §4.3, §6.5-§6.9): the usability ladder
-- poll, known ranks, talents, totems, the target's cast, enemies, health, stats.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

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
        ctl.known[fs.REND], ctl.known[fs.REND_R2] = true, true
        ctl.Fire("SPELLS_CHANGED")
        assert.are.equal(fs.REND_R2, I.ab.qid[3])
        ctl.usable[fs.REND_R2] = { true, false }
        ctl.usable[fs.STRIKE] = { fake.SECRET, false }
        drain(5)
        local r = VS.Power(fs.RAGE, 5)
        assert.are.equal(10, r.lo) -- rend's rung; heroic strike's secret answer is no news
    end)

    it("walks the talent tree into ranks by registered spell ID, and defers a walk in combat", function()
        ctl.traits = { config = 1, trees = { 7 }, nodeIDs = { 70 }, nodes = {}, defs = { [700] = 12286 } }
        ctl.traits.nodes[70] = { entryIDs = { 700 }, activeRank = 2 }
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.are.equal(2, VS.Talent(12286))
        local gen = VS.TalentGen()
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.traits.nodes[70].activeRank = 3
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.are.equal(2, VS.Talent(12286))
        ctl.Fire("PLAYER_REGEN_ENABLED")
        drain(6)
        assert.are.same({ 3, gen + 1 }, { VS.Talent(12286), VS.TalentGen() })
        assert.are.equal(0, VS.Talent(99999))
        assert.are.equal("unused", S.status["talent walk aliases"])
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
        assert.are.equal(1, VS.Count.InRange(fs.REND, 3))
    end)

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
end)
