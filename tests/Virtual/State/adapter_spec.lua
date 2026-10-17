-- tests/Virtual/State/adapter_spec.lua: Adapter.lua against the fake spec provider (spec §3.6, §4.6, §5): the tracked
-- set from the registrations, and Drain (the fold; our casts' effects are Families/Now.lua's, see now_spec.lua).
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local fs = require("Virtual.State.helpers.fake_spec")

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

    it("opens the snapshot log with one failure line when Snapshot raises, and Hekili's setup still runs", function()
        local lines, setup = {}, 0
        local hk = fs.new(9)
        function hk:SetupDebug()
            setup = setup + 1
        end
        function hk:Debug(fmt, ...)
            lines[#lines + 1] = string.format(fmt, ...)
        end
        load.adapter(ns, hk)
        hk.ActiveDebug = true
        local snapshot = VS.Snapshot
        VS.Snapshot = function()
            error("snap boom", 0)
        end
        local ok = pcall(hk.SetupDebug, hk, "Primary")
        VS.Snapshot = snapshot
        assert.is_true(ok)
        assert.are.equal(1, setup)
        assert.are.same({ "[vs] snapshot failed: snap boom" }, lines)
    end)

    it("builds the tracked set from the registrations", function()
        local out = {}
        assert.are.equal(3, VS.Tracked("ability", out))
        assert.are.same({ fs.SPENDER_A, fs.SPENDER_B, fs.SPENDER_C }, out)
        assert.are.equal(2, VS.Tracked("aura", out))
        assert.are.equal(1, VS.Tracked("resource", out))
        assert.are.same({ fs.RAGE }, out)
        assert.are.equal(2, VS.Tracked("unit", out))
        assert.are.equal(1, I.res.swing[1]) -- the mainhand swing model makes rage swing-paid
        -- the debug handle only: the client is Hekili.Client (Facade.lua), and the alias is gone
        assert.are.same({ VS, I.Events }, { h.Virtual.State, h.Virtual.Events })
        assert.is_nil(h.Virtual.API)
        assert.is_nil(h.VirtualState)
    end)

    it("builds the tracked set's contents: ids from id and copy, spender slots, talents de-duplicated", function()
        local got
        local build = I.Build
        I.Build = function(def, t)
            got = def
            return build(def, t)
        end
        h.Class.talents.talent_a_alias = { 0, 1011, 3 } -- the same talent spell under a second key
        h.Class.abilities.spender_b.copy = 1006 -- a number `copy`
        h.Class.abilities.spender_a_nospend = { key = "spender_a_nospend", id = 1005, funcs = {} } -- no spend: slot 0
        VS.SpecChanged()
        I.Build = build
        assert.are.same(
            { { fs.SPENDER_A }, { 1005 }, { fs.SPENDER_B, 1006 }, { fs.SPENDER_C, fs.SPENDER_C_R2 } },
            got.abilityIds
        )
        assert.are.same({ 1, 0, 1, 1 }, got.abilitySlot)
        assert.are.same({ { fs.SPENDER_A }, { fs.SPENDER_C, fs.SPENDER_C_R2 } }, got.auraIds)
        assert.are.equal(1, #got.talents)
        assert.are.equal(1011, got.talents[1].spell)
    end)

    it("reads each ability's GCD kind and a declared gcdTime from Hekili's ability table as it is", function()
        h.Class.abilities.spender_t = { key = "spender_t", id = fs.SPENDER_T, gcd = "totem", funcs = {} }
        h.Class.abilities.spender_u = { key = "spender_u", id = fs.SPENDER_U, gcdTime = 0.8, funcs = {} }
        VS.SpecChanged()
        local A, kinds = I.ab, {}
        for a = 1, A.n do
            kinds[A.key[a]] = A.gcdKind[a]
        end
        assert.are.same({ spender_a = 1, spender_b = 0, spender_c = 1, spender_t = 2, spender_u = 1 }, kinds)
        assert.are.equal(0.8, A.obj[A.bySpell[fs.SPENDER_U]].gcdTime)
    end)

    it("forwards a resource's player-aura regen entries to the resources family", function()
        h.Class.resources.rage.state.regenModel.regen_aura_a = { aura = "regen_aura_a", interval = 1, value = 1 }
        h.Class.resources.rage.state.regenModel.debuff_test =
            { aura = "spender_c", debuff = true, interval = 3, value = 2 }
        h.Class.auras.regen_aura_a = { key = "regen_aura_a", id = 1021, duration = 10 }
        VS.SpecChanged()
        local G = I.res.auraRegen
        assert.are.equal(1, G.n) -- the debuff entry is not a player aura
        assert.are.same({ 1, 1, 1 }, { G.slot[1], G.value[1], G.interval[1] })
        assert.are.equal(1021, I.auras.id[G.aura[1]])
        assert.are.equal(1, I.res.swing[1]) -- the swing source is still found
    end)

    it("forwards the off hand's swing value and a plain periodic entry (combat-gated), with its talent", function()
        local model = h.Class.resources.rage.state.regenModel
        model.offhand = { swing = "offhand", value = 4 }
        model.regen_talent_a = { talent = "talent_a", interval = 3, value = 1 }
        VS.SpecChanged()
        assert.are.same({ 1, 9, 4 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
        local G = I.res.auraRegen
        assert.are.same({ 1, 0, 1, 3, 1011 }, { G.n, G.aura[1], G.value[1], G.interval[1], G.talent[1] })
        model.shield_test = { equip = "shield", interval = 2, value = 1 } -- a gate VirtualState cannot see: dropped
        model.channel_test = { channel = "spender_c", interval = 1, value = 1 }
        VS.SpecChanged()
        assert.are.equal(1, I.res.auraRegen.n)
        model.shield_test, model.channel_test = nil, nil
        model.mainhand = nil -- an off hand alone pays as the paying hand
        VS.SpecChanged()
        assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
    end)

    it("forwards the paying entry's `taken`, bound to the `now` context, and no other entry's", function()
        local model = h.Class.resources.rage.state.regenModel
        local function taken()
            return buff.spender_a.up and 3 or 1 -- luacheck: ignore 113 (the `now` context's names)
        end
        model.mainhand.taken = taken
        model.offhand = { swing = "offhand", value = 4, taken = function() end } -- not the paying entry: unread
        VS.SpecChanged()
        assert.are.equal(taken, I.res.taken[1])
        assert.are.equal(I.nowCtx, getfenv(taken))
        model.mainhand.taken, model.offhand = nil, nil
        VS.SpecChanged()
        assert.is_false(I.res.taken[1])
    end)

    it(
        "generates the sim's `__taken` entry: every second from the reset, the learned rate, out of combat removed",
        function()
            local model = h.Class.resources.rage.state.regenModel
            VS.SpecChanged()
            assert.is_nil(model.__taken) -- no `taken`: none
            model.mainhand.taken = function()
                return 2
            end
            local got
            local build = I.Build
            I.Build = function(def, t)
                got = def
                return build(def, t)
            end
            VS.SpecChanged()
            local e = model.__taken
            VS.SpecChanged()
            I.Build = build
            assert.are.same({ e, "rage", 1 }, { model.__taken, e.resource, e.interval }) -- built once
            assert.is_nil(got.resources[1].auraRegen) -- the walk skips it: not a regen entry of the belief
            state.time, state.now, state.offset = 0, 20, 0
            assert.are.same({ true, 0 }, { e.stop(), e.value() }) -- out of combat
            I.Sources.Direct(VS.Obs.CombatStart, 10)
            I.Sources.Direct(VS.Obs.PlayerHit, 12, 1, 40, 20)
            I.Sources.Direct(VS.Obs.PlayerHit, 15, 4, 0, 20)
            I.Fold(15)
            state.time, state.now, state.offset = 5, 16, 1.5
            assert.are.same({ false, 0.4, 17 }, { e.stop(), e.value(), e.last() }) -- 2 + 2 in 10 s; from the reset
            assert.are.equal(18, e.last() + e.interval) -- 1.5 s on, the next beat is the reset's +2, not +2.5
            state.offset = 2
            assert.are.equal(18, e.last()) -- a beat at the forecast's start is already in `actual`
            model.mainhand.taken = nil
            VS.SpecChanged()
            assert.is_nil(model.__taken) -- the paying entry lost its `taken`: removed
        end
    )

    it("generates the sim's stepped decay entry, on the belief's beats and from a tick aura's expiry", function()
        local model, rank = h.Class.resources.rage.state.regenModel, 0
        model.regen_aura_a = { aura = "regen_aura_a", interval = 1, value = 1, pausesDecay = true }
        h.Class.auras.regen_aura_a = { key = "regen_aura_a", id = 1021, duration = 10 }
        h.Class.resources.rage.state.meta = {
            decay = function()
                return 2 * (1 - 0.3 * rank)
            end,
            decayInterval = function()
                return 1
            end,
        }
        VS.SpecChanged()
        local e = model.__decay
        assert.are.same({ "rage", 1, -2 }, { e.resource, e.interval(), e.value() })
        rank = 1
        assert.is_true(math.abs(-1.4 - e.value()) < 1e-9) -- the talent's 30% less
        local got
        local build = I.Build
        I.Build = function(def, t)
            got = def
            return build(def, t)
        end
        VS.SpecChanged()
        I.Build = build
        assert.are.same({ e, 1 }, { model.__decay, I.res.auraRegen.n }) -- built once; not a regen entry of the belief
        assert.are.same({ model.regen_aura_a }, got.resources[1].auraRegen) -- the walk skips it, the second build too
        state.time, state.now, state.buff.regen_aura_a = 0, 4.5, { up = false, expires = 0 }
        assert.are.same({ false, 3.5 }, { e.stop(), e.last() }) -- the belief at rest: a quantum at the forecast's start
        state.time = 5
        assert.is_true(e.stop()) -- in combat
        I.Sources.Direct(VS.Obs.CombatStart, 1.5)
        I.Fold(1.5)
        I.ResourceShift(1, 50, 1.5, VS.Obs.CastSuccess)
        I.Sources.Direct(VS.Obs.CombatEnd, 2)
        I.Fold(2)
        I.Settle(3.5) -- the belief's quanta at 2 and 3, the next at 4
        state.now = 3.5 -- the reset at the belief's clock
        assert.are.same({ 3, 3 }, { VS.DecayAnchor(fs.RAGE), e.last() }) -- the sim's next beat: 4, the belief's
        state.buff.regen_aura_a = { up = true, expires = 20 }
        assert.are.equal(19, e.last()) -- a tick aura up in the sim: the first quantum at its expiry, after its tick
        state.buff.regen_aura_a = { up = false, expires = 0 }
        state.now, state.offset = 5, 2.5 -- after an advance: actual holds the beats at 4 to 7
        assert.are.equal(7, e.last()) -- the forecast's first beat at 8, none re-applied
        state.buff.regen_aura_a = { up = true, expires = 20.5 }
        assert.are.equal(19.5, e.last())
        state.offset = 18.7 -- the sim advanced to 23.7, past the expiry the reset saw: beats at 20.5 to 23.5
        state.buff.regen_aura_a.up = false
        assert.are.equal(23.5, e.last()) -- not the belief's anchor's beats (23): it is paused while the aura is up
        model.regen_aura_a.pausesDecay = nil -- unflagged: an aura up in the sim moves no beat
        state.now, state.offset, state.buff.regen_aura_a = 5, 2.5, { up = true, expires = 20 }
        assert.are.equal(7, e.last())
    end)

    it("forwards a regenerating resource's rest as a flag and a swing entry's `aura` as its gate", function()
        local got
        local build = I.Build
        I.Build = function(def, t)
            got = def
            return build(def, t)
        end
        VS.SpecChanged()
        assert.are.same({ false, nil }, { got.resources[1].rest, got.resources[1].swingAura })
        ns.ResourceRegenerates = function(k)
            return k == "rage"
        end
        h.Class.resources.rage.state.regenModel.mainhand.aura = "bear_form"
        VS.SpecChanged()
        I.Build = build
        assert.are.same({ true, "bear_form" }, { got.resources[1].rest, got.resources[1].swingAura })
    end)

    it(
        "leaves the cast history, the real queue and the swing fields to the combat-log rows, asks for a cycle",
        function()
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.casting = { 1000, 2500 }
            ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", fs.SPENDER_C)
            ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-3", fs.SPENDER_C)
            assert.are.same({}, state.history) -- CLEU_HANDLER writes them from the rows (cleu_rows_spec)
            assert.are.same({}, state.removed)
            assert.are.same({}, state.queue)
            assert.are.same({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_FAILED" }, h.forced)
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            assert.are.equal(0, state.swings.mh_actual) -- CLEU_HANDLER writes it from the swing row
        end
    )

    it(
        "folds a swing staged this frame before poll 3 clears the queued strike: the swing is skipped as paid",
        function()
            ctl.current[fs.SPENDER_B] = true
            ctl.now = 2
            VS.Drain(2)
            assert.is_true(I.queuedStrike)
            local before = VS.Power(fs.RAGE, 2).est
            ctl.now = 3
            ctl.Fire("PLAYER_SWING", 2.6, 0) -- staged; the flush frame has not ticked
            ctl.current[fs.SPENDER_B] = nil -- the strike took that swing
            VS.Drain(3)
            assert.is_false(I.queuedStrike)
            ctl.Tick(3.05)
            ctl.now = 3.1
            VS.Drain(3.1)
            assert.are.equal(before, VS.Power(fs.RAGE, 3.1).est) -- no swing income
        end
    )

    it("never resets or replays Hekili's state in the drain, and marks a unit whose believed auras moved", function()
        ctl.now = 3
        VS.Drain(3)
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.Tick(5.05)
        VS.Drain(5.1)
        assert.are.same({ 0, 0, 0 }, { state.resets, state.offset, state.delay })
        assert.is_true(state.target.updated) -- spender_c's `now` moved the target's set
        assert.are.equal(1, I.drainCasts)
    end)
end)
