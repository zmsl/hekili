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
        ctl.usable[fs.SPENDER_C] = { true, false } -- rage >= 10 (the poll's rung)
        ctl.now = 4
        VS.Drain(4)
        ctl.usable[fs.SPENDER_C] = nil
        cast(fs.SPENDER_C, 5)
        local rage = VS.Power(fs.RAGE, 5.1)
        assert.are.same({ 0, "modelled", 5 }, { rage.est, rage.basis, rage.last.modelled.t })
        local spender_c, stacks = VS.Aura("target", fs.SPENDER_C, 5.1)
        assert.are.same({ 20, "modelled", 1 }, { spender_c.est, spender_c.basis, stacks })
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
        cast(fs.SPENDER_C, 5)
        assert.are.same({ "SPELL_AURA_APPLIED", "Creature-1", fs.SPENDER_C, "DEBUFF", nil, 5 }, rows[#rows])
        cast(fs.SPENDER_C, 8)
        assert.are.same({ "SPELL_AURA_REFRESH", 8 }, { rows[#rows][1], rows[#rows][6] })
        ctl.Tick(23.5) -- past spender_c's modelled expiry (8 + 15)
        assert.are.same({ "SPELL_AURA_REMOVED", "Creature-1", fs.SPENDER_C, "DEBUFF", nil, 23.5 }, rows[#rows])
        cast(fs.SPENDER_A, 30)
        assert.are.same(
            { "SPELL_AURA_APPLIED", "Player-1", fs.SPENDER_A, "BUFF" },
            { rows[#rows][1], rows[#rows][2], rows[#rows][3], rows[#rows][4] }
        )
        local shout = VS.Aura("player", fs.SPENDER_A, 30.1)
        assert.are.equal(150, shout.est) -- the aura's registered duration (120) when the `now` passes none
    end)

    it("pays an on-next-swing strike's cost at its success, which arrives with its swing", function()
        start()
        cast(fs.SPENDER_B, 14)
        local rage = VS.Power(fs.RAGE, 14.1)
        assert.are.equal(14, rage.last.modelled.t)
        assert.are.equal(-15, I.res.pinDelta[1])
    end)

    it("lets a later observation win over a `now` write, and not an earlier one", function()
        start()
        local j = I.auras.bySpell[fs.SPENDER_C]
        I.Sources.Direct(VS.Obs.Read, 4.9, I.AURA_UNIT + j, 0, I.ReadOf.Aura) -- an earlier read: down
        cast(fs.SPENDER_C, 5)
        assert.are.equal("modelled", VS.Aura("target", fs.SPENDER_C, 5.5).basis)
        I.Sources.Direct(VS.Obs.Read, 6, I.AURA_UNIT + j, 0, I.ReadOf.Aura) -- a newer read: down
        I.Fold(6.5)
        assert.is_nil(VS.Aura("target", fs.SPENDER_C, 6.5))
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

    -- reads the real Warrior.lua by design: this checks a content file's `now` in the core context (as the scan below)
    it("believes Warrior.lua's Battle Shout up on us for its 180 s from a rank 3 cast (6192)", function()
        local w = require("Forever.helpers.load_warrior").load()
        local a, aura = w.abilities.battle_shout, w.auras.battle_shout
        register("battle_shout", { id = a.id, copy = a.copy, spend = 10, spendType = "rage", now = a.now })
        h.Class.auras.battle_shout = { key = "battle_shout", id = aura.id, copy = aura.copy, duration = aura.duration }
        start()
        cast(6192, 40)
        local rec = VS.Aura("player", aura.id, 40.1)
        assert.are.same({ 220, "modelled" }, { rec.est, rec.basis })
        assert.are.equal(0, I.nowErrors)
    end)

    -- Every Forever ability whose sim `handler` (or a channel's `start`) changes an aura or gains a resource declares
    -- a `now`: the belief never runs the sim handler, and own auras are secret in combat. A text scan of the files.
    local EXEMPT = {
        heroic_strike = "the queued-strike pseudo-aura has no spell id: untracked; poll 3 reads the queue",
        cleave = "as heroic_strike",
        maul = "as heroic_strike",
        revenge = "revenge_usable has no spell id: untracked",
        starfire = "removeStack is no `now` verb; the charges end with the 15 s aura",
        claw = "combo points are read plainly in combat (poll 1)",
        shred = "as claw",
        healthstone = "health is no tracked resource",
    }
    it("declares a `now` beside every handler with an aura or resource effect", function()
        local VERB = {
            "applyBuff%(",
            "applyDebuff%(",
            "removeBuff%(",
            "removeDebuff%(",
            "addStack%(",
            "removeStack%(",
            "gain%(",
            "swap_stance%(",
            "swap_form%(",
        }
        local missing, scanned = {}, 0
        local files = {}
        for _, path in ipairs(require("helpers.addons").lua(require("helpers.addons").CONTENT)) do
            files[#files + 1] = path
        end
        for _, path in ipairs(files) do
            local fh = assert(io.open(path))
            local text = fh:read("*a")
            fh:close()
            local function check(key, body, ind)
                local sim = body:match("\n" .. ind .. "handler = function%(%)(.-)\n" .. ind .. "end,")
                    or body:match("\n" .. ind .. "start = function%(%)(.-)\n" .. ind .. "end,")
                if not sim then
                    return
                end
                for _, v in ipairs(VERB) do
                    if sim:find(v) then
                        scanned = scanned + 1
                        if not body:find("\n" .. ind .. "now = function") and not EXEMPT[key] then
                            missing[#missing + 1] = path .. ": " .. key
                        end
                        return
                    end
                end
            end
            -- multi-line opens only: a one-line entry (a talent row) must not swallow the next ability
            for key, body in text:gmatch("\n    ([%w_]+) = ({\n.-)\n    },") do
                check(key, body, "        ")
            end
            for key, body in text:gmatch('RegisterAbility%("([%w_]+)", {(.-)\n}%)') do
                check(key, body, "    ")
            end
        end
        assert.is_true(scanned > 60, "the scan found " .. scanned .. " handlers") -- the patterns still match
        table.sort(missing)
        assert.are.same({}, missing)
    end)

    it("runs removeBuff, spend, addStack and setCooldown through the context with Hekili's signatures", function()
        register("verbs_test", {
            id = 6161,
            now = function()
                removeBuff("spender_a")
                spend(4, "rage")
                addStack("spender_c", 15, 2)
                setCooldown("verbs_test", 30)
            end,
        })
        h.Class.auras.spender_c.max_stack = 5 -- addStack clamps at max_stack (1 when none), as Hekili's does
        start()
        cast(fs.SPENDER_A, 20) -- spender_a up (its `now`)
        local before = VS.Power(fs.RAGE, 21)
        local est = before.est
        cast(6161, 21)
        assert.is_nil(VS.Aura("player", fs.SPENDER_A, 21.1)) -- removeBuff
        assert.are.equal(math.max(est - 4, 0), VS.Power(fs.RAGE, 21.1).est) -- spend
        local spender_c, stacks = VS.Aura("player", fs.SPENDER_C, 21.1)
        assert.are.same({ 36, 2 }, { spender_c.est, stacks }) -- addStack( aura, duration, stacks ) on us
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
        local a = I.ab.bySpell[fs.SPENDER_C]
        local gen = VS.AuraGen("target")
        pcall(I.ab.now[a]) -- as DevTools' RunStressTest calls every function in ability.funcs
        assert.are.equal(gen, VS.AuraGen("target"))
        assert.is_nil(VS.Aura("target", fs.SPENDER_C, 1.5))
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
        cast(fs.SPENDER_C, 31)
        assert.are.equal(31 + 15, VS.Aura("target", fs.SPENDER_C, 31.1).est)
        assert.is_truthy(VS.Snapshot():find("errors=1", 1, true))
    end)

    it("reads talents, auras and resources through the context and answers knownRank from the belief", function()
        local seen = {}
        register("read_test", {
            id = 5151,
            now = function()
                seen.rank = talent.talent_a.rank
                seen.none = talent.not_a_talent.rank
                seen.spender_c = debuff.spender_c.up
                seen.shout = buff.spender_a.remains
                seen.rage = rage.current
                seen.known = knownRank({ fs.SPENDER_C, fs.SPENDER_C_R2 })
                seen.t = now
            end,
        })
        start()
        I.SetTalentRank(1, 2)
        cast(fs.SPENDER_C, 40)
        cast(5151, 41)
        assert.are.same({ 2, 0, true, 0, 41 }, { seen.rank, seen.none, seen.spender_c, seen.shout, seen.t })
        assert.is_number(seen.rage)
        assert.are.equal(0, seen.known) -- no rank in the fake spellbook
        ctl.known[fs.SPENDER_C_R2] = true
        ctl.Fire("SPELLS_CHANGED")
        cast(5151, 42)
        assert.are.equal(2, seen.known)
    end)

    it("KnownID answers a tracked ability's known rank id, else its input unchanged (core edit E5)", function()
        start()
        assert.are.equal(fs.SPENDER_C, VS.KnownID(fs.SPENDER_C)) -- no rank known yet
        ctl.known[fs.SPENDER_C_R2] = true
        ctl.Fire("SPELLS_CHANGED")
        assert.are.equal(fs.SPENDER_C_R2, VS.KnownID(fs.SPENDER_C))
        assert.are.equal(fs.SPENDER_C_R2, VS.KnownID(fs.SPENDER_C_R2))
        assert.are.equal(424242, VS.KnownID(424242)) -- untracked
        assert.is_nil(VS.KnownID(nil))
        assert.are.equal("spender_c", VS.KnownID("spender_c"))
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

    it(
        "models the automatic GCD by kind: totem t + 1.0, spell t + 1.5 / haste, a declared gcdTime, the learned slot",
        function()
            register("totem_test", { id = 4501, gcd = "totem" })
            register("fixed_test", { id = 4502, gcdTime = 0.8 })
            start()
            cast(4501, 10)
            assert.are.equal(11, VS.Gcd(10.1).est)
            cast(fs.SPENDER_C, 20)
            assert.are.equal(21.5, VS.Gcd(20.1).est) -- haste 1
            cast(4502, 30)
            assert.are.equal(30.8, VS.Gcd(30.1).est)
            I.gcdLearned[1] = 1.4 -- the spell kind's learned length (Families/Casts.lua's falling edge)
            cast(fs.SPENDER_C, 40)
            assert.are.equal(41.4, VS.Gcd(40.1).est)
            cast(4501, 50)
            assert.are.equal(51, VS.Gcd(50.1).est) -- the totem kind keeps its own
        end
    )

    it(
        "models a spell-kind cast at t + 1.5 after three totem ones learned 1.0, and the next totem one at t + 1.0",
        function()
            register("totem_test", { id = 4501, gcd = "totem" })
            start()
            for _, t in ipairs({ 10, 12, 14 }) do
                cast(4501, t)
                I.Sources.Direct(VS.Obs.Cooldown, t, 0, 1, 1) -- the GCD's edges, 1.0 s apart
                I.Sources.Direct(VS.Obs.Cooldown, t + 1, 0, 0, 1)
                VS.Drain(t + 1.01)
            end
            assert.are.same({ 0, 1 }, I.gcdLearned)
            cast(fs.SPENDER_C, 16)
            assert.are.equal(17.5, VS.Gcd(16.1).est)
            cast(4501, 18)
            assert.are.equal(19, VS.Gcd(18.1).est)
        end
    )

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

    describe("a stacking aura's cast beside a plain read of it", function()
        local j
        local function stackCast()
            h.Class.auras.sunder_test = { key = "sunder_test", id = 7386, duration = 30, max_stack = 5 }
            register("stack_test", {
                id = 7387,
                now = function()
                    addStack("sunder_test", 30, 1)
                end,
            })
            start()
            j = I.auras.bySpell[7386]
        end
        local function read(t, stacks) -- a plain read of the player's aura, logged at once (the cast is staged)
            I.Sources.Direct(VS.Obs.Read, t, j, 30, I.ReadOf.Aura + stacks * I.AURA_STACK)
        end
        local function stacks(t)
            return select(2, VS.Aura("player", 7386, t))
        end

        it("lets a read in the cast's frame win: the cast's stack is not added on top of it", function()
            stackCast()
            read(5, 1)
            cast(7387, 5)
            assert.are.same({ 1, "observed" }, { stacks(5.1), VS.Aura("player", 7386, 5.1).basis })
            read(6, 2)
            cast(7387, 6)
            assert.are.equal(2, stacks(6.1))
            assert.are.equal(2, I.auraReadsWon)
            assert.is_truthy(VS.Snapshot():find("aura reads won=2", 1, true))
        end)

        it("adds a stack per cast when no read is in the frame", function()
            stackCast()
            cast(7387, 5)
            assert.are.equal(1, stacks(5.1))
            read(5.5, 1) -- an older frame's read does not stop the next cast
            cast(7387, 6)
            assert.are.same({ 2, "modelled" }, { stacks(6.1), VS.Aura("player", 7386, 6.1).basis })
            assert.are.equal(0, I.auraReadsWon)
        end)

        it("applies a cast on a new target despite the old target's read in the same frame", function()
            start()
            local k = I.auras.bySpell[fs.SPENDER_C]
            I.Sources.Direct(VS.Obs.Read, 5, I.AURA_UNIT + k, 30, I.ReadOf.Aura + I.AURA_STACK) -- target A: up
            I.Sources.Direct(VS.Obs.TargetSwap, 5, 2, 1, 1) -- to target B (slot 2)
            cast(fs.SPENDER_C, 5)
            local rec, n = VS.Aura("target", fs.SPENDER_C, 5.1)
            assert.are.same({ "modelled", 1 }, { rec.basis, n })
            assert.are.equal(0, I.auraReadsWon)
        end)

        it("lets a read after the modelled change win, as before", function()
            stackCast()
            cast(7387, 5)
            read(5.5, 3)
            I.Fold(5.6)
            assert.are.same({ 3, "observed" }, { stacks(5.6), VS.Aura("player", 7386, 5.6).basis })
        end)
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
                applyDebuff("target", "spender_c", 15)
                local _ = talent.talent_a.rank + rage.current
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
            cast(fs.SPENDER_C, t + 0.5)
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
        ctl.Fire("PLAYER_TARGET_CHANGED") -- a target GUID, so spender_c's rows have a destination
        local t = 50
        local emitted = I.Log.emitted
        local bytes = alloc.bytes(function()
            t = t + 20
            cast(fs.SPENDER_C, t) -- SPELL_AURA_APPLIED
            cast(2687, t + 1) -- SPELL_ENERGIZE
            ctl.Tick(t + 16) -- past spender_c's modelled expiry: SPELL_AURA_REMOVED
        end, 1000)
        assert.are.equal(0, bytes)
        assert.is_true(I.Log.emitted - emitted >= 1200 * 5) -- two casts, an aura, an energize and a removal each
    end)
end)
