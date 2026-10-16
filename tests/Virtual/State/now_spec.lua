-- tests/Virtual/State/now_spec.lua (event-facade spec §12a): a cast's effects on the belief. The automatic ones from the
-- ability's declared fields (cost, cooldown, GCD) and the class file's `now` function, run in VirtualState's context
-- with Hekili's verb names, as `modelled` samples at the cast's time; never Hekili's `state`.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local fs = require("Virtual.State.helpers.fake_spec")
local alloc = require("Virtual.State.helpers.alloc")

describe("now handlers", function()
    local ns, VS, I, api, ctl, h, state, saved, rows, cleu

    local function register(key, t)
        t.key, t.funcs = key, { now = t.now }
        t.now = nil
        t.cast, t.cooldown, t.charges, t.recharge = t.cast or 0, t.cooldown or 0, t.charges or 1, t.recharge or 0
        h.Class.abilities[key], h.Class.abilities[t.id] = t, t
    end

    local function cast(id, t)
        ctl.now = t
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
        ctl.Tick(t + 0.01)
        VS.Drain(t + 0.02)
        ctl.Tick(t + 0.03) -- the drain's rows reach Hekili at the next delivery point
    end

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "issecretvalue", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue =
            api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
        _G.debugprofilestop = function()
            return 0
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
        rows = {}
        cleu = I.Events.CreateFrame("Frame")
        cleu:SetScript("OnEvent", function()
            local _, sub, _, _, _, _, _, dst, _, _, _, spellID, _, _, a15, _, a17 =
                ns.Facade.CombatLogGetCurrentEventInfo()
            rows[#rows + 1] = { sub, dst, spellID, a15, a17, ns.Facade.GetTime() }
        end)
        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    local function start()
        VS.Start(api)
        VS.SpecChanged()
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end

    it("writes the cost, the GCD and the `now` debuff as modelled samples at the cast's time", function()
        start()
        ctl.usable[fs.REND] = { true, false } -- rage >= 10 (the poll's rung)
        ctl.now = 4
        VS.Drain(4)
        ctl.usable[fs.REND] = nil
        cast(fs.REND, 5)
        local rage = VS.Power(fs.RAGE, 5.1)
        assert.are.same({ 0, "modelled", 5 }, { rage.est, rage.basis, rage.last.modelled.t })
        local rend, stacks = VS.Aura("target", fs.REND, 5.1)
        assert.are.same({ 20, "modelled", 1 }, { rend.est, rend.basis, stacks })
        assert.are.equal("modelled", VS.Gcd(5.1).basis)
        assert.is_true(VS.Gcd(5.1).est > 5)
        assert.are.same({ 0, 0, 0 }, { state.resets, state.offset, state.delay }) -- Hekili's state untouched
    end)

    it("shifts a resource by `gain` (est, lo and hi) and writes its energize row back-dated to the cast", function()
        register("rage_test", {
            id = 2687,
            cooldown = 60,
            now = function()
                gain(10, "rage")
            end,
        })
        start()
        local before = VS.Power(fs.RAGE, 9)
        local est, lo, hi = before.est, before.lo, before.hi
        cast(2687, 9)
        local after = VS.Power(fs.RAGE, 9.1)
        assert.are.same({ est + 10, lo + 10, math.min(hi + 10, 100) }, { after.est, after.lo, after.hi })
        assert.are.same(
            { "modelled", 9, VS.Obs.CastSuccess },
            { after.basis, after.last.modelled.t, after.last.modelled.event }
        )
        assert.are.equal(0, state.rage.actual) -- the `now` never touches Hekili's state
        assert.are.same({ "SPELL_ENERGIZE", "Player-1", 2687, 10, fs.RAGE, 9 }, rows[#rows])
        assert.is_true(VS.Cooldown(2687, 9.1).est > 60) -- the declared cooldown
    end)

    it("emits our casts' aura rows: APPLIED, REFRESH back-dated, REMOVED at the modelled expiry", function()
        start()
        ctl.Fire("PLAYER_TARGET_CHANGED")
        cast(fs.REND, 5)
        assert.are.same({ "SPELL_AURA_APPLIED", "Creature-1", fs.REND, "DEBUFF", nil, 5 }, rows[#rows])
        cast(fs.REND, 8)
        assert.are.same({ "SPELL_AURA_REFRESH", 8 }, { rows[#rows][1], rows[#rows][6] })
        ctl.Tick(23.5) -- past Rend's modelled expiry (8 + 15)
        assert.are.same({ "SPELL_AURA_REMOVED", "Creature-1", fs.REND, "DEBUFF", nil, 23.5 }, rows[#rows])
        cast(fs.SHOUT, 30)
        assert.are.same(
            { "SPELL_AURA_APPLIED", "Player-1", fs.SHOUT, "BUFF" },
            { rows[#rows][1], rows[#rows][2], rows[#rows][3], rows[#rows][4] }
        )
        local shout = VS.Aura("player", fs.SHOUT, 30.1)
        assert.are.equal(150, shout.est) -- the aura's registered duration (120) when the `now` passes none
    end)

    it("pays an on-next-swing strike's cost at its success, which arrives with its swing", function()
        start()
        cast(fs.STRIKE, 14)
        local rage = VS.Power(fs.RAGE, 14.1)
        assert.are.equal(14, rage.last.modelled.t)
        assert.are.equal(-15, I.res.pinDelta[1])
    end)

    it("lets a later observation win over a `now` write, and not an earlier one", function()
        start()
        local j = I.auras.bySpell[fs.REND]
        I.Sources.Direct(VS.Obs.Read, 4.9, I.AURA_UNIT + j, 0, I.ReadOf.Aura) -- an earlier read: down
        cast(fs.REND, 5)
        assert.are.equal("modelled", VS.Aura("target", fs.REND, 5.5).basis)
        I.Sources.Direct(VS.Obs.Read, 6, I.AURA_UNIT + j, 0, I.ReadOf.Aura) -- a newer read: down
        I.Fold(6.5)
        assert.is_nil(VS.Aura("target", fs.REND, 6.5))
    end)

    it("changes only cost, cooldown and GCD for an ability without `now`", function()
        register("plain_test", { id = 4444, cooldown = 6, spend = 5, spendType = "rage" })
        start()
        local gen = VS.AuraGen("player") + VS.AuraGen("target")
        local n = #rows
        cast(4444, 12)
        assert.are.equal(gen, VS.AuraGen("player") + VS.AuraGen("target"))
        assert.are.equal("modelled", VS.Cooldown(4444, 12.1).basis)
        local rage = VS.Power(fs.RAGE, 12.1)
        assert.are.equal(12, rage.last.modelled.t) -- the cost, written at the cast (the ladder's pin ties it)
        assert.are.equal(n + 1, #rows) -- only the cast's own SPELL_CAST_SUCCESS row
    end)

    it("runs removeBuff, spend, addStack and setCooldown through the context with Hekili's signatures", function()
        register("verbs_test", {
            id = 6161,
            now = function()
                removeBuff("battle_shout")
                spend(4, "rage")
                addStack("rend", 15, 2)
                setCooldown("verbs_test", 30)
            end,
        })
        h.Class.auras.rend.max_stack = 5 -- addStack clamps at max_stack (1 when none), as Hekili's does
        start()
        cast(fs.SHOUT, 20) -- Battle Shout up (its `now`)
        local before = VS.Power(fs.RAGE, 21)
        local est = before.est
        cast(6161, 21)
        assert.is_nil(VS.Aura("player", fs.SHOUT, 21.1)) -- removeBuff
        assert.are.equal(math.max(est - 4, 0), VS.Power(fs.RAGE, 21.1).est) -- spend
        local rend, stacks = VS.Aura("player", fs.REND, 21.1)
        assert.are.same({ 36, 2 }, { rend.est, stacks }) -- addStack( aura, duration, stacks ) on us
        local cd = VS.Cooldown(6161, 21.1)
        assert.are.same({ 51, "modelled" }, { cd.est, cd.basis }) -- setCooldown( action, duration )
        assert.are.equal("SPELL_AURA_REMOVED", rows[#rows - 1][1])
    end)

    it("counts a gain or spend naming no tracked resource as the `now`'s error, writing nothing", function()
        register("bad_test", {
            id = 6262,
            now = function()
                gain(10, "health")
            end,
        })
        start()
        local est = VS.Power(fs.RAGE, 22).est
        cast(6262, 22)
        assert.are.equal(1, I.nowErrors)
        assert.is_truthy(tostring(I.nowError):find("health", 1, true))
        assert.are.equal(est, VS.Power(fs.RAGE, 22.1).est)
    end)

    it("writes nothing when a `now` runs outside a cast (RunStressTest, an APL reading action.x.now)", function()
        start()
        local a = I.ab.bySpell[fs.REND]
        local gen = VS.AuraGen("target")
        pcall(I.ab.now[a]) -- as DevTools' RunStressTest calls every function in ability.funcs
        assert.are.equal(gen, VS.AuraGen("target"))
        assert.is_nil(VS.Aura("target", fs.REND, 1.5))
    end)

    it("gives a tracked extra (VS.Track) no effects: no GCD, no cooldown", function()
        I.extra.abilities[#I.extra.abilities + 1] = 9898
        start()
        local g = VS.Gcd(30).basis
        cast(9898, 30)
        assert.are.equal(g, VS.Gcd(30.1).basis)
        assert.are.equal(0, I.castsRun)
    end)

    it("counts a raising `now` and keeps folding the observations after it", function()
        register("boom_test", {
            id = 7777,
            now = function()
                error("now raised")
            end,
        })
        start()
        cast(7777, 30)
        assert.are.equal(1, I.nowErrors)
        assert.is_truthy(tostring(I.nowError):find("now raised"))
        cast(fs.REND, 31)
        assert.are.equal(31 + 15, VS.Aura("target", fs.REND, 31.1).est)
        assert.is_truthy(VS.Snapshot():find("errors=1", 1, true))
    end)

    it("reads talents, auras and resources through the context and answers knownRank from the belief", function()
        local seen = {}
        register("read_test", {
            id = 5151,
            now = function()
                seen.rank = talent.improved_rend.rank
                seen.none = talent.not_a_talent.rank
                seen.rend = debuff.rend.up
                seen.shout = buff.battle_shout.remains
                seen.rage = rage.current
                seen.known = knownRank({ 772, 6546 })
                seen.t = now
            end,
        })
        start()
        I.SetTalentRank(1, 2)
        cast(fs.REND, 40)
        cast(5151, 41)
        assert.are.same({ 2, 0, true, 0, 41 }, { seen.rank, seen.none, seen.rend, seen.shout, seen.t })
        assert.is_number(seen.rage)
        assert.are.equal(0, seen.known) -- no rank in the fake spellbook
        ctl.known[fs.REND_R2] = true
        ctl.Fire("SPELLS_CHANGED")
        cast(5151, 42)
        assert.are.equal(2, seen.known)
    end)

    it("KnownID answers a tracked ability's known rank id, else its input unchanged (core edit E5)", function()
        start()
        assert.are.equal(fs.REND, VS.KnownID(fs.REND)) -- no rank known yet
        ctl.known[fs.REND_R2] = true
        ctl.Fire("SPELLS_CHANGED")
        assert.are.equal(fs.REND_R2, VS.KnownID(fs.REND))
        assert.are.equal(fs.REND_R2, VS.KnownID(fs.REND_R2))
        assert.are.equal(424242, VS.KnownID(424242)) -- untracked
        assert.is_nil(VS.KnownID(nil))
        assert.are.equal("Rend", VS.KnownID("Rend"))
        assert.are.equal(VS.KnownID, ns.KnownSpellID)
    end)

    it("anchors a GCD at a hard cast's start once: a later instant cast of the same ability starts its own", function()
        register("slam_test", { id = 1464, cast = 1.5 })
        start()
        ctl.now = 10
        ctl.casting = { 10000, 11500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", 1464)
        ctl.Tick(10.05)
        ctl.casting = nil
        cast(1464, 11.5)
        assert.are.equal(0, I.ab.castStartT[I.ab.bySpell[1464]])
        cast(1464, 20) -- instant this time
        local gcd = VS.Gcd(20.1)
        assert.are.equal("modelled", gcd.basis)
        assert.is_true(gcd.est > 20)
    end)

    it("clears a stopped cast's start", function()
        register("slam_test", { id = 1464, cast = 1.5 })
        start()
        ctl.now = 10
        ctl.casting = { 10000, 11500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", 1464)
        ctl.Tick(10.05)
        ctl.casting = nil
        ctl.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-3", 1464)
        ctl.Tick(10.5)
        VS.Drain(10.5)
        assert.are.equal(0, I.ab.castStartT[I.ab.bySpell[1464]])
    end)

    it(
        "spends a charge from the count caught up to the cast: recharges finished since the last sample count",
        function()
            register("charge_test", { id = 3131, charges = 2, recharge = 10 })
            start()
            local a = I.ab.bySpell[3131]
            I.ab.charges0[a], I.ab.next0[a] = 1, 10
            cast(3131, 25) -- the recharge at 10 finished: 2 charges at the cast
            local ch, nx = VS.Charges(3131, 25.1)
            assert.are.same({ 1, 35 }, { ch.est, nx.est })
        end
    )

    it("clamps addStack at the aura's max_stack", function()
        h.Class.auras.sunder_test = { key = "sunder_test", id = 7386, duration = 30, max_stack = 5 }
        register("stack_test", {
            id = 7387,
            now = function()
                addStack("sunder_test", 30, 3)
            end,
        })
        start()
        cast(7387, 5)
        cast(7387, 6)
        local _, stacks = VS.Aura("player", 7386, 6.1)
        assert.are.equal(5, stacks)
    end)

    it("reaches no game API, no Hekili state and no _G from a `now`", function()
        local seen = {}
        -- compiled apart, so `state` is the global name, not this file's upvalue
        local make = loadstring(
            "local seen = ... return function() seen[1], seen[2], seen[3] = type(state), type(GetTime), type(_G) end"
        )
        register("iso_test", { id = 6363, now = make(seen) })
        start()
        cast(6363, 5)
        assert.are.same({ "nil", "nil", "nil" }, seen)
    end)

    it("counts a `now` assigning a global as its error, and the verbs survive it", function()
        register("glob_test", {
            id = 6464,
            now = function()
                gain = nil -- luacheck: ignore 121
            end,
        })
        start()
        cast(6464, 5)
        assert.are.equal(1, I.nowErrors)
        assert.is_truthy(tostring(I.nowError):find("gain", 1, true))
        assert.is_function(I.nowCtx.gain)
    end)

    it("skips and counts a `now` that is the ability's own handler (its environment stays Hekili's)", function()
        local f = function() end
        register("same_test", { id = 6565, now = f })
        h.Class.abilities.same_test.funcs.handler = f
        local env = getfenv(f)
        start()
        assert.is_false(I.ab.now[I.ab.bySpell[6565]])
        assert.are.equal(1, I.nowErrors)
        assert.are.equal(env, getfenv(f))
    end)

    it("allocates nothing across 1000 casts with `now` handlers", function()
        register("rage_test", {
            id = 2687,
            now = function()
                gain(1, "rage")
                applyDebuff("target", "rend", 15)
                local _ = talent.improved_rend.rank + rage.current
            end,
        })
        register("charge_test", { id = 3131, charges = 2, recharge = 10 }) -- the charge step too
        start()
        function h:ForceUpdate() end -- the fake records each call; Hekili's own only sets fields
        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- the capturing subscriber allocates by design
        local t = 50
        local bytes = alloc.bytes(function()
            t = t + 1
            cast(2687, t)
            cast(fs.REND, t + 0.5)
            cast(3131, t + 0.7)
        end, 1000)
        assert.are.equal(0, bytes)
    end)

    it("allocates nothing emitting aura rows, an energize row and the modelled-expiry REMOVED at the tick", function()
        register("rage_test", {
            id = 2687,
            now = function()
                gain(1, "rage")
            end,
        })
        start()
        function h:ForceUpdate() end
        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        ctl.Fire("PLAYER_TARGET_CHANGED") -- a target GUID, so Rend's rows have a destination
        local t = 50
        local emitted = I.Log.emitted
        local bytes = alloc.bytes(function()
            t = t + 20
            cast(fs.REND, t) -- SPELL_AURA_APPLIED
            cast(2687, t + 1) -- SPELL_ENERGIZE
            ctl.Tick(t + 16) -- past Rend's modelled expiry: SPELL_AURA_REMOVED
        end, 1000)
        assert.are.equal(0, bytes)
        assert.is_true(I.Log.emitted - emitted >= 1200 * 5) -- two casts, an aura, an energize and a removal each
    end)
end)
