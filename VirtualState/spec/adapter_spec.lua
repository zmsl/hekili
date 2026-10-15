-- VirtualState/spec/adapter_spec.lua: Adapter.lua against the fake spec provider (spec §3.6, §4.6, §5): the tracked
-- set from the registrations, the across-reset feeds, and Drain's apply through the spec (the read-before /
-- read-after diff as `modelled` samples, two full resets, the offset restored, `updated` marked). The apply against
-- the real `state` is verified in game (spec §11).
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("Adapter", function()
    local ns, VS, I, api, ctl, h, state, saved

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame = api.GetTime, api.UnitGUID, api.CreateFrame
        _G.debugprofilestop = function()
            return os.clock() * 1000
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        h = fs.new(9)
        state = h.State
        fs.clock = api.GetTime
        ns.spendResources = fs.spend
        ns.ResourceRegenerates = function()
            return false
        end
        load.adapter(ns, h)
        VS.Start(api)
        VS.SpecChanged()
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    it("builds the tracked set from the registrations", function()
        local out = {}
        assert.are.equal(3, VS.Tracked("ability", out))
        assert.are.same({ fs.SHOUT, fs.STRIKE, fs.REND }, out)
        assert.are.equal(2, VS.Tracked("aura", out))
        assert.are.equal(1, VS.Tracked("resource", out))
        assert.are.same({ fs.RAGE }, out)
        assert.are.equal(2, VS.Tracked("unit", out))
        assert.are.equal(1, I.res.swing[1]) -- the mainhand swing model makes rage swing-paid
        assert.are.equal(h.VirtualState or VS, VS)
    end)

    it("builds the tracked set's contents: ids from id and copy, spender slots, talents de-duplicated", function()
        local got
        local build = I.Build
        I.Build = function(def, t)
            got = def
            return build(def, t)
        end
        h.Class.talents.improved_rend_alias = { 0, 12286, 3 } -- the same talent spell under a second key
        h.Class.abilities.heroic_strike.copy = 285 -- a number `copy`
        h.Class.abilities.charge_test = { key = "charge_test", id = 100, funcs = {} } -- no spend: slot 0
        VS.SpecChanged()
        I.Build = build
        assert.are.same({ { fs.SHOUT }, { 100 }, { fs.STRIKE, 285 }, { fs.REND, fs.REND_R2 } }, got.abilityIds)
        assert.are.same({ 1, 0, 1, 1 }, got.abilitySlot)
        assert.are.same({ { fs.SHOUT }, { fs.REND, fs.REND_R2 } }, got.auraIds)
        assert.are.equal(1, #got.talents)
        assert.are.equal(12286, got.talents[1].spell)
    end)

    it("feeds the cast history and the real queue from our own cast events, and asks for a cycle", function()
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
        assert.are.same({ "rend" }, state.history)
        assert.are.same({ "rend:CAST_FINISH" }, state.removed)
        assert.are.same({ "UNIT_SPELLCAST_SUCCEEDED" }, h.forced)
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2", fs.REND) -- never STARTed: the source ignores it
        assert.are.same({ "rend:CAST_FINISH" }, state.removed)
        ctl.casting = { 1000, 2500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", fs.REND)
        assert.are.same({ "rend:CAST_FINISH" }, state.queue)
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-3", fs.REND)
        assert.are.same({ "rend:CAST_FINISH", "rend:CAST_FINISH" }, state.removed)
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        assert.are.same({ 1, 3.6 }, { state.swings.mh_actual, state.swings.mh_projected })
    end)

    it("applies an instant cast through the spec: modelled rage, GCD and debuff, two resets, offset restored", function()
        ctl.usable[fs.REND] = { true, false } -- rage >= 10 (the poll's rung)
        ctl.now = 4
        VS.Drain(4)
        ctl.usable[fs.REND] = nil -- no answer after the cast
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
        ctl.Tick(5.05)
        ctl.now = 5.1
        VS.Drain(5.1)
        assert.are.equal(2, state.resets)
        assert.are.same({ 0, 0 }, { state.offset, state.delay })
        assert.is_nil(I.pinned)
        assert.are.equal(5 - 0.01, state.combat) -- rend starts combat (R2)
        local rage = VS.Power(fs.RAGE, 5.1)
        assert.are.equal("modelled", rage.basis)
        assert.are.same({ 0, 0 }, { rage.est, rage.lo }) -- 10 seen at the poll, then 10 spent
        assert.are.same({ 0, 5 }, { rage.last.modelled.v, rage.last.modelled.t })
        local rend = VS.Aura("target", fs.REND, 5.1)
        assert.are.same({ 20, "modelled" }, { rend.est, rend.basis })
        assert.is_true(state.target.updated)
        assert.are.same({ 6.5, "modelled" }, { VS.Gcd(5.1).est, VS.Gcd(5.1).basis })
        assert.are.equal(1, I.drainCasts)
    end)

    -- A test ability on the fake spec, registered under its key and its spell ID.
    local function register(key, t)
        t.key, t.funcs = key, {}
        t.charges, t.recharge = 1, 0
        h.Class.abilities[key], h.Class.abilities[t.id] = t, t
    end

    local function near(want, got)
        assert.is_true(math.abs(want - got) < 1e-6, ("want %s, got %s"):format(want, got))
    end

    it("applies a hard cast at its finish: the GCD at the start's time, CAST_FINISH through HandleEvent", function()
        register("slam_test", { id = 1464, cast = 1.5, cooldown = 0, spend = 15, spendType = "rage" })
        VS.SpecChanged()
        I.ObsLog.Clear(I.log)
        ctl.now = 10
        ctl.casting = { 10000, 11500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", 1464)
        assert.are.same({ "slam_test:CAST_FINISH" }, state.queue) -- the real queue's finish, as CLEU queued it
        ctl.Tick(10.05)
        ctl.now = 11.5
        ctl.casting = nil
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 1464)
        assert.are.same({ "slam_test:CAST_FINISH" }, state.removed) -- removed on success
        ctl.Tick(11.55)
        ctl.now = 11.6
        VS.Drain(11.6)
        assert.are.equal("slam_test", state.handled) -- HandleEvent ran the finish
        near(11.5, state.cooldown.slam_test.expires) -- at the success time
        near(11.5, VS.Gcd(11.6).est) -- the GCD began at the start (10 + 1.5)
        assert.are.equal("modelled", VS.Gcd(11.6).basis)
        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
    end)

    it("applies a channel at its start and feeds its finish and ticks; CHANNEL_STOP removes them", function()
        local ran = false
        register("drain_test", {
            id = 5555,
            channeled = true,
            cast = 3,
            tick_time = 1,
            cooldown = 10,
            handler = function()
                ran = true
            end,
        })
        VS.SpecChanged()
        I.ObsLog.Clear(I.log)
        ctl.now = 20
        ctl.channel = { 20000, 23000 }
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 5555)
        assert.are.same(
            { "drain_test:CHANNEL_FINISH", "drain_test:CHANNEL_TICK", "drain_test:CHANNEL_TICK" },
            state.queue
        )
        ctl.Tick(20.05)
        ctl.now = 20.1
        VS.Drain(20.1)
        assert.is_true(ran) -- the handler
        local cd = VS.Cooldown(5555, 20.1)
        near(30, cd.est) -- the cooldown step at the channel's start
        assert.are.equal("modelled", cd.basis)
        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", 5555)
        assert.are.same({ "drain_test:all" }, state.removed)
    end)

    it("folds a swing staged this frame before poll 3 clears the queued strike: the swing is skipped as paid", function()
        ctl.current[fs.STRIKE] = true
        ctl.now = 2
        VS.Drain(2)
        assert.is_true(I.queuedStrike)
        local before = VS.Power(fs.RAGE, 2).est
        ctl.now = 3
        ctl.Fire("PLAYER_SWING", 2.6, 0) -- staged; the flush frame has not ticked
        ctl.current[fs.STRIKE] = nil -- the strike took that swing
        VS.Drain(3)
        assert.is_false(I.queuedStrike)
        ctl.Tick(3.05)
        ctl.now = 3.1
        VS.Drain(3.1)
        assert.are.equal(before, VS.Power(fs.RAGE, 3.1).est) -- no swing income
    end)

    it("counts a raising apply and still restores: unpinned, offset 0, the trailing reset run", function()
        register("boom_test", {
            id = 7777,
            cooldown = 0,
            handler = function()
                error("spec handler raised")
            end,
        })
        VS.SpecChanged()
        I.ObsLog.Clear(I.log)
        ctl.now = 30
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 7777)
        ctl.Tick(30.05)
        ctl.now = 30.1
        VS.Drain(30.1)
        assert.is_nil(I.pinned)
        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
        assert.are.equal(1, I.applyErrors)
        assert.are.equal(0, I.drainCasts)
        assert.is_truthy(VS.Snapshot():find("errors=1", 1, true))
        assert.is_truthy(VS.Snapshot():find("spec handler raised", 1, true))
    end)

    it("counts a raising first reset, skips the apply and still restores", function()
        local reset, raised = state.reset, false
        state.reset = function()
            if not raised then
                raised = true
                error("reset raised")
            end
            reset()
        end
        ctl.now = 32
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-8", fs.REND)
        ctl.Tick(32.05)
        ctl.now = 32.1
        assert.has_no.errors(function()
            VS.Drain(32.1)
        end)
        assert.is_nil(I.pinned)
        assert.are.same({ 0, 0, 1 }, { state.offset, state.delay, state.resets }) -- only the trailing reset ran
        assert.are.same({ 1, 0 }, { I.applyErrors, I.drainCasts })
        assert.is_truthy(VS.Snapshot():find("reset raised", 1, true))
    end)

    it("runs no reset for an own cast of a tracked extra with no ability", function()
        I.extra.abilities[1] = 6666
        VS.SpecChanged()
        I.extra.abilities[1] = nil
        I.ObsLog.Clear(I.log)
        ctl.now = 34
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 6666)
        ctl.Tick(34.05)
        ctl.now = 34.1
        VS.Drain(34.1)
        assert.are.same({ 0, 0, 0 }, { state.resets, I.applyErrors, I.drainCasts })
    end)

    it("rescans both units at the trailing reset, so an untracked apply-time aura write does not survive", function()
        register("untracked_test", {
            id = 8888,
            cooldown = 0,
            handler = function()
                state.applyBuff("untracked_buff", 30)
            end,
        })
        VS.SpecChanged()
        I.ObsLog.Clear(I.log)
        local reset = state.reset
        state.reset = function() -- as Hekili's reset: an `updated` unit is scraped afresh (State.lua:6199-6207)
            reset()
            if state.player.updated then
                state.buff.untracked_buff = nil -- the scrape finds no such aura
                state.player.updated = false
            end
            if state.target.updated then
                state.target.updated = false
            end
        end
        ctl.now = 40
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 8888)
        ctl.Tick(40.05)
        ctl.now = 40.1
        VS.Drain(40.1)
        assert.are.equal(2, state.resets)
        assert.is_nil(state.buff.untracked_buff)
    end)

    it("marks no unit after the trailing reset rescanned both, even when the believed auras moved", function()
        local reset = state.reset
        state.reset = function() -- a scrape clears `updated` (State.lua:6199-6207)
            reset()
            state.player.updated, state.target.updated = false, false
        end
        ctl.now = 42
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", fs.REND)
        ctl.Tick(42.05)
        ctl.now = 42.1
        local gen = VS.AuraGen("target")
        VS.Drain(42.1)
        assert.are_not.equal(gen, VS.AuraGen("target")) -- rend's debuff moved the target's set
        assert.are.same({ 2, false, false }, { state.resets, state.player.updated, state.target.updated })
    end)

    it("queues a hard cast's finish with a nil target when the sent GUID is unknown, reading no GUID", function()
        register("slam_test", { id = 1464, cast = 1.5, cooldown = 0 })
        VS.SpecChanged()
        local target, calls = false, 0
        function state:QueueEvent(key, start, finish, eType, guid)
            target = guid
        end
        local unitGUID = api.UnitGUID
        api.UnitGUID = function(unit)
            calls = calls + 1
            return unitGUID(unit)
        end
        I.sentGUID = nil
        ctl.now = 50
        ctl.casting = { 50000, 51500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-7", 1464)
        api.UnitGUID = unitGUID
        assert.is_nil(target)
        assert.are.equal(0, calls)
    end)

    it("runs no reset when the log holds no own cast", function()
        ctl.now = 3
        VS.Drain(3)
        assert.are.equal(0, state.resets)
    end)
end)
