-- tests/Game/State/tracked_spec.lua: the core's build of the tracked set (Engine/Schema/Tracked.lua) against the fake
-- spec provider (spec §3.6, §4.6, §5): the set from the registrations, VS.Build, and Drain (the fold; our casts'
-- effects are Families/Now.lua's, see now_spec.lua).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the tracked set", function()
    local ns, VS, I, api, ctl, h, state, saved

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame = api.GetTime, api.UnitGUID, api.CreateFrame
        local clockMs = 0 -- one ms per read: a timed span of two reads measures exactly 1
        _G.debugprofilestop = function()
            clockMs = clockMs + 1
            return clockMs
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
        load.schema(ns, h)
        VS.Start(api)
        ns.BuildTracked()
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
        assert.are.same({ fs.SPENDER_A, fs.SPENDER_B, fs.SPENDER_C }, out)
        assert.are.equal(2, VS.Tracked("aura", out))
        assert.are.equal(1, VS.Tracked("resource", out))
        assert.are.same({ fs.RAGE }, out)
        assert.are.equal(2, VS.Tracked("unit", out))
        assert.are.equal(1, I.res.swing[1]) -- the mainhand swing model makes rage swing-paid
        assert.is_nil(h.Virtual) -- the debug bridge is the core's (Hekili.lua), not the build's
    end)

    it("carries the core's game constants in the build, and the belief reads them from it alone", function()
        ns.FSR, ns.GCD_SPELL, ns.ORACLE_MIN = 7, 4242, 0.3
        ns.BuildTracked()
        assert.are.same({ 7, 4242, 0.3 }, { I.FSR, I.GCD_SPELL, I.Log.ORACLE_MIN })
        assert.are.same({ 7, 4242, 0.3 }, { I.def.fsr, I.def.gcdSpell, I.def.oracleMin })
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
        ns.BuildTracked()
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

    it("carries the declared gear as plain records: sets and items by piece IDs, bonuses by aura spell", function()
        local got
        local build = I.Build
        I.Build = function(def, t)
            got = def
            return build(def, t)
        end
        h.Class.gear = {
            idol = { 900001, [900001] = true }, -- RegisterGear's shape (Engine/Schema/Spec.lua)
            set = { 900011, 900012, [900011] = true, [900012] = true },
        }
        h.Class.setBonuses = { set_5pc = 900021 }
        ns.BuildTracked()
        I.Build = build
        assert.are.same({
            { key = "idol", items = { 900001 } },
            { key = "set", items = { 900011, 900012 } },
            { key = "set_5pc", aura = 900021 },
        }, got.gear)
        h.Class.gear, h.Class.setBonuses = nil, nil
        ns.BuildTracked()
        assert.are.same({}, I.def.gear) -- a class without gear: an empty list, wiped each build
    end)

    it("reads each ability's GCD kind and a declared gcdTime from Hekili's ability table as it is", function()
        h.Class.abilities.spender_t = { key = "spender_t", id = fs.SPENDER_T, gcd = "totem", funcs = {} }
        h.Class.abilities.spender_u = { key = "spender_u", id = fs.SPENDER_U, gcdTime = 0.8, funcs = {} }
        ns.BuildTracked()
        local A, kinds = I.ab, {}
        for a = 1, A.n do
            kinds[A.key[a]] = A.gcdKind[a]
        end
        assert.are.same({ spender_a = 1, spender_b = 0, spender_c = 1, spender_t = 2, spender_u = 1 }, kinds)
        assert.are.equal(0.8, A.obj[A.bySpell[fs.SPENDER_U]].gcdTime)
    end)

    it("builds plain records: no metatable, `funcs` flattened, the declared `spend` as the record's", function()
        h.Class.abilities.spender_a.funcs.usable = function()
            return true
        end
        ns.BuildTracked()
        local rec = I.ab.obj[I.ab.bySpell[fs.SPENDER_A]]
        assert.is_nil(getmetatable(rec))
        assert.is_nil(rec.funcs)
        assert.are.equal("function", type(rec.usable))
        assert.are.equal(10, rec.spend)
        assert.are_not.equal(h.Class.abilities.spender_a, rec) -- a copy, never Hekili's table
        assert.is_nil(getmetatable(I.auras.obj[1]))
    end)

    it("computes a function field's static value after the talents, not at the build", function()
        local f = function()
            return 10 - talent.talent_a.rank -- luacheck: ignore 113 (the simulation's names, the context's too)
        end
        setfenv(f, h.State) -- as Spec.lua binds a pack's function
        h.Class.abilities.spender_a.cooldown, h.Class.abilities.spender_a.funcs.cooldown = nil, f
        h.State.talent = { talent_a = { rank = 0 } }
        ns.BuildTracked() -- Spec.lua's order: the build, then ns.updateTalents, then ns.TrackedStatics
        local a = I.ab.bySpell[fs.SPENDER_A]
        assert.is_nil(I.ab.obj[a].static)
        h.State.talent.talent_a.rank = 2 -- what updateTalents learns from the build's talent walk
        ns.TrackedStatics()
        assert.are.equal(8, I.ab.obj[a].static.cooldown)
        local errors = I.nowErrors
        assert.are.equal(10, I.CooldownOf(a, 1)) -- the function in the belief's context first: its own rank (unwalked, 0)
        assert.are.equal(errors, I.nowErrors)
        h.State.sim = h.State
        I.ab.obj[a].cooldown = setfenv(function()
            return 10 - sim.talent.talent_a.rank -- luacheck: ignore 113 (a name the context lacks: raises there)
        end, h.State)
        assert.are.equal(8, I.CooldownOf(a, 1)) -- raised in the context (counted): the static, never 0
        assert.are.equal(errors + 1, I.nowErrors)
    end)

    it("takes a working function's nil as its answer, never its static (nil while its talent is unranked)", function()
        local f = function()
            return talent.talent_a.rank > 0 and 1.0 or nil -- luacheck: ignore 113 (a talent's value, or none)
        end
        local g = function()
            return talent.talent_a.rank > 0 and 15 or nil -- luacheck: ignore 113
        end
        local s = function()
            return talent.talent_a.rank > 0 and 20 or nil -- luacheck: ignore 113
        end
        setfenv(f, h.State)
        setfenv(g, h.State)
        setfenv(s, h.State)
        h.Class.abilities.spender_a.gcdTime, h.Class.abilities.spender_a.funcs.gcdTime = nil, f
        h.Class.abilities.spender_a.cooldown, h.Class.abilities.spender_a.funcs.cooldown = nil, g
        h.Class.abilities.spender_a.spend, h.Class.abilities.spender_a.funcs.spend = nil, s
        h.State.talent = { talent_a = { rank = 2 } } -- the sim's rank: the statics are 1.0, 15 and 20
        ns.BuildTracked()
        ns.TrackedStatics()
        local a = I.ab.bySpell[fs.SPENDER_A]
        local static = I.ab.obj[a].static
        assert.are.same({ 1.0, 15, 20 }, { static.gcdTime, static.cooldown, static.spend })
        local errors = I.nowErrors
        -- the belief's rank is 0 (unwalked): nil is the answer, not a failure: no declared GCD time, cooldown or cost
        assert.are.equal(1.5, I.GcdLen(a, 1)) -- the spell kind's default, not the static 1.0
        assert.are.equal(0, I.CooldownOf(a, 1))
        assert.are.equal(0, I.BaseCostOf(a)) -- not the static 20
        assert.are.equal(errors, I.nowErrors)
    end)

    it("forwards a resource's player-aura regen entries to the resources family", function()
        h.Class.resources.rage.state.regenModel.regen_aura_a = { aura = "regen_aura_a", interval = 1, value = 1 }
        h.Class.resources.rage.state.regenModel.debuff_test =
            { aura = "spender_c", debuff = true, interval = 3, value = 2 }
        h.Class.auras.regen_aura_a = { key = "regen_aura_a", id = 1021, duration = 10 }
        ns.BuildTracked()
        local G = I.res.auraRegen
        assert.are.equal(1, G.n) -- the debuff entry is not a player aura
        assert.are.same({ 1, 1, 1 }, { G.slot[1], G.value[1], G.interval[1] })
        assert.are.equal(1021, I.auras.id[G.aura[1]])
        assert.are.equal(1, I.res.swing[1]) -- the swing source is still found
    end)

    it("forwards a resource's `fsr` meta and its `mult` entries (C3, C3b)", function()
        local st = h.Class.resources.rage.state
        st.meta = { fsr = { spirit = 3, mp5 = 1 } }
        st.regenMult = { { aura = "regen_aura_a", mult = 2 } }
        h.Class.auras.regen_aura_a = { key = "regen_aura_a", id = 1021, duration = 10 }
        ns.BuildTracked()
        local M = I.res.regenMult
        assert.are.same({ true, 1, 3, 1, 2 }, { I.res.fsr[1], I.res.regE[1], I.res.spE[1], M.n, M.mult[1] })
        assert.are.equal(1021, I.auras.id[M.aura[1]])
    end)

    it("forwards the off hand's swing value and a plain periodic entry (combat-gated), with its talent", function()
        local model = h.Class.resources.rage.state.regenModel
        model.offhand = { swing = "offhand", value = 4 }
        model.regen_talent_a = { talent = "talent_a", interval = 3, value = 1 }
        ns.BuildTracked()
        assert.are.same({ 1, 9, 4 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
        local G = I.res.auraRegen
        assert.are.same({ 1, 0, 1, 3, 1011 }, { G.n, G.aura[1], G.value[1], G.interval[1], G.talent[1] })
        model.shield_test = { equip = "shield", interval = 2, value = 1 } -- a gate VirtualState cannot see: dropped
        model.channel_test = { channel = "spender_c", interval = 1, value = 1 }
        ns.BuildTracked()
        assert.are.equal(1, I.res.auraRegen.n)
        model.shield_test, model.channel_test = nil, nil
        model.mainhand = nil -- an off hand alone pays as the paying hand
        ns.BuildTracked()
        assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
    end)

    it("forwards the paying entry's `taken`, bound to the `now` context, and no other entry's", function()
        local model = h.Class.resources.rage.state.regenModel
        local function taken()
            return buff.spender_a.up and 3 or 1 -- luacheck: ignore 113 (the `now` context's names)
        end
        model.mainhand.taken = taken
        model.offhand = { swing = "offhand", value = 4, taken = function() end } -- not the paying entry: unread
        ns.BuildTracked()
        assert.are.equal(taken, I.res.taken[1])
        assert.are.equal(I.nowCtx, getfenv(taken))
        model.mainhand.taken, model.offhand = nil, nil
        ns.BuildTracked()
        assert.is_false(I.res.taken[1])
    end)

    it("reads a function `fsr` part to a number at the build, the spec's tree being the core's fact", function()
        local meta = {}
        h.Class.resources.rage.state.meta = meta
        meta.fsr = {
            spirit = function()
                return 12
            end,
            mp5 = function()
                error("boom")
            end,
            share = 0.5,
        }
        local errors = {}
        local was = ns.Error
        ns.Error = function(msg)
            errors[#errors + 1] = msg
        end
        ns.BuildTracked()
        ns.Error = was
        local fsr = I.def.resources[I.res.slotOf[h.Class.resources.rage.type]].fsr
        h.Class.resources.rage.state.meta = nil
        assert.are.same({ spirit = 12, share = 0.5 }, fsr)
        assert.are.equal(1, #errors)
    end)

    it(
        "skips the sim's own generated entries (`__decay`, `__taken`: Engine/Schema/Spec/Regen.lua's) in the walk",
        function()
            local model = h.Class.resources.rage.state.regenModel
            model.__decay = { resource = "rage", interval = 1 }
            model.__taken = { resource = "rage", interval = 1 }
            model.regen_aura_a = { aura = "regen_aura_a", interval = 1, value = 1 }
            h.Class.auras.regen_aura_a = { key = "regen_aura_a", id = 1021, duration = 10 }
            local got
            local build = I.Build
            I.Build = function(def, t)
                got = def
                return build(def, t)
            end
            ns.BuildTracked()
            I.Build = build
            assert.are.same({ model.regen_aura_a }, got.resources[1].auraRegen) -- the two names are no regen entries
            assert.are.equal(1, I.res.auraRegen.n)
            model.__decay, model.__taken, model.regen_aura_a = nil, nil, nil
        end
    )

    it("forwards a regenerating resource's rest as a flag and a swing entry's `aura` as its gate", function()
        local got
        local build = I.Build
        I.Build = function(def, t)
            got = def
            return build(def, t)
        end
        ns.BuildTracked()
        assert.are.same({ false, nil }, { got.resources[1].rest, got.resources[1].swingAura })
        ns.ResourceRegenerates = function(k)
            return k == "rage"
        end
        h.Class.resources.rage.state.regenModel.mainhand.aura = "bear_form"
        ns.BuildTracked()
        I.Build = build
        assert.are.same({ true, "bear_form" }, { got.resources[1].rest, got.resources[1].swingAura })
    end)

    it("leaves the cast history, the real queue and the swing fields to the combat-log rows", function()
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.casting = { 1000, 2500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", fs.SPENDER_C)
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-3", fs.SPENDER_C)
        assert.are.same({}, state.history) -- CLEU_HANDLER writes them from the rows (cleu_rows_spec)
        assert.are.same({}, state.removed)
        assert.are.same({}, state.queue) -- the cycle is Hekili's own handlers' (border batch 2, E14)
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        assert.are.equal(0, state.swings.mh_actual) -- CLEU_HANDLER writes it from the swing row
    end)

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

    -- A UNIT_AURA subscriber (Hekili's handler, Events.lua): records each delivery's unit and a copy of its lists.
    local function auraSubscriber()
        local log = {}
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, _, unit, data)
            local e = { unit = unit, full = data.isFullUpdate, added = {}, updated = {}, removed = {} }
            for _, a in ipairs(data.addedAuras or {}) do
                e.added[#e.added + 1] = { a.spellId, a.auraInstanceID, a.isFromPlayerOrPlayerPet }
            end
            for _, id in ipairs(data.updatedAuraInstanceIDs or {}) do
                e.updated[#e.updated + 1] = id
            end
            for _, id in ipairs(data.removedAuraInstanceIDs or {}) do
                e.removed[#e.removed + 1] = id
            end
            log[#log + 1] = e
        end)
        f:RegisterUnitEvent("UNIT_AURA", "player", "target")
        return log
    end

    it("never resets or replays Hekili's state in the drain, and delivers a moved unit's believed delta", function()
        local log = auraSubscriber()
        ctl.now = 3
        VS.Drain(3)
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.Tick(5.05)
        assert.are.equal(0, #log) -- the delta is the drain's (inside Hekili.Update, before its resets), not the event's
        VS.Drain(5.1)
        assert.are.same({ 0, 0, 0 }, { state.resets, state.offset, state.delay })
        assert.are.equal(1, I.drainCasts)
        assert.is_false(state.target.updated) -- Hekili's own handler sets it; the drain writes no Hekili state
        assert.are.equal(1, #log) -- spender_c's `now` moved the target's set: UNIT_AURA(target, { addedAuras })
        local rec, _, _, inst = VS.Aura("target", fs.SPENDER_C, 5.1)
        assert.is_truthy(rec)
        assert.are.same(
            { unit = "target", full = nil, added = { { fs.SPENDER_C, inst, true } }, updated = {}, removed = {} },
            log[1]
        )
    end)

    it("delivers a refresh as updatedAuraInstanceIDs and a modelled expiry as removedAuraInstanceIDs", function()
        local log = auraSubscriber()
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.Tick(5.05)
        VS.Drain(5.1)
        local inst = select(4, VS.Aura("target", fs.SPENDER_C, 5.1))
        ctl.now = 8
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_C) -- a refresh: the instance stays
        ctl.Tick(8.05)
        VS.Drain(8.1)
        assert.are.equal(2, #log)
        assert.are.same({ unit = "target", added = {}, updated = { inst }, removed = {} }, log[2])
        ctl.now = 30 -- past the 15 s duration: the settle models it down
        ctl.Tick(30)
        VS.Drain(30)
        assert.are.equal(3, #log)
        assert.are.same({ unit = "target", added = {}, updated = {}, removed = { inst } }, log[3])
        assert.is_nil((VS.Aura("target", fs.SPENDER_C, 30)))
    end)

    it("profiles the registry's rows and the polls only while Prof.on is set", function()
        local prof = I.Prof
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 1)
        VS.Drain(ctl.now)
        assert.are.same({ 0, 0, 0, 0 }, { prof.rows, prof.polls, prof.rowMs, prof.pollMs })
        prof.on = true
        ctl.now = 2
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 11, 1)
        VS.Drain(ctl.now)
        assert.are.same({ 1, 1, 1, 1 }, { prof.rows, prof.polls, prof.rowMs, prof.pollMs })
    end)
end)
