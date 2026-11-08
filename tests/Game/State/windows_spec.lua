-- tests/Game/State/windows_spec.lua (re-pin design §3a, decision 11; plan Task 8a): the belief's rotation windows. Each
-- window's evaluator runs once per Drain after the fold, in the `now` context; its edges, duration, caps, combat end,
-- steps, strictness and the `now` verbs; read through Facade.Window. Allocates nothing per Drain.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

-- free test abilities: three steps and an unrelated one on the GCD, one off it, and one whose `now` opens a window
local ONE, TWO, THREE, OTHER, OFF, OPENER = 3001, 3002, 3003, 3004, 3005, 3006

describe("rotation windows (belief)", function()
    local ns, VS, I, api, ctl, h, saved

    local function register(key, t)
        t.key, t.funcs = key, { now = t.now }
        t.now = nil
        t.cast, t.cooldown, t.charges, t.recharge = t.cast or 0, t.cooldown or 0, t.charges or 1, t.recharge or 0
        h.Class.abilities[key], h.Class.abilities[t.id] = t, t
    end

    -- the record Spec.lua's RegisterWindow stores (Engine/Schema/Spec.lua)
    local function declare(key, t)
        t.key = key
        t.on_deviation = t.on_deviation or "stay"
        h.Class.windows = h.Class.windows or {}
        h.Class.windows[key] = t
    end

    local function drain(t)
        ctl.now = t
        ctl.Tick(t)
        VS.Drain(t)
    end

    local function cast(id, t)
        ctl.now = t
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
        ctl.Tick(t + 0.01)
        VS.Drain(t + 0.02)
    end

    local function W(name)
        return { ns.Facade.Window(name) }
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
        fs.clock = api.GetTime
        ns.spendResources = fs.spend
        ns.ResourceRegenerates = function()
            return false
        end
        load.schema(ns, h)
        register("w_one", { id = ONE })
        register("w_two", { id = TWO })
        register("w_three", { id = THREE })
        register("w_other", { id = OTHER })
        register("w_off", { id = OFF, gcd = "off" })
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    local function start()
        VS.Start(api)
        ns.BuildTracked()
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end

    describe("edges", function()
        local on
        local function flagged(key, t)
            t.evaluator = function()
                return on
            end
            t.duration = t.duration or 6
            declare(key, t)
        end
        before_each(function()
            on = false
        end)

        it("opens on false->true only, and a condition held true does nothing", function()
            flagged("w", {})
            start()
            drain(2)
            assert.are.same({ false, 0, 0, 0, 0 }, W("w"))
            on = true
            drain(3)
            assert.are.same({ true, 3, 9, 0, 0 }, W("w"))
            drain(4)
            drain(5)
            drain(6)
            assert.are.same({ true, 3, 9, 0, 0 }, W("w"))
        end)

        it("with refresh, restarts the duration once per new edge", function()
            flagged("w", { refresh = true })
            start()
            on = true
            drain(3)
            on = false
            drain(4)
            on = true
            drain(5)
            drain(6)
            assert.are.same({ true, 3, 11, 1, 0 }, W("w"))
        end)

        it("max_refresh = 1 refuses the second refresh", function()
            flagged("w", { refresh = true, max_refresh = 1 })
            start()
            for k, t in ipairs({ 3, 4, 5, 6, 7 }) do
                on = k % 2 == 1
                drain(t)
            end
            assert.are.same({ true, 3, 11, 1, 0 }, W("w"))
        end)

        it("max_duration bounds the span from the first open", function()
            flagged("w", { refresh = true, max_duration = 8 })
            start()
            for k, t in ipairs({ 3, 4, 5, 6, 7 }) do
                on = k % 2 == 1
                drain(t)
            end
            assert.are.same({ true, 3, 11, 2, 0 }, W("w")) -- 7 + 6 capped at 3 + 8
            drain(11)
            assert.is_false(W("w")[1])
        end)

        it("with refresh and no cap, keeps refreshing", function()
            flagged("w", { refresh = true })
            start()
            local t = 3
            for k = 1, 21 do
                on = k % 2 == 1
                drain(t)
                t = t + 1
            end
            assert.are.same({ true, 3, 29, 10, 0 }, W("w"))
        end)

        it("expires at its duration", function()
            flagged("w", {})
            start()
            on = true
            drain(3)
            drain(8.99)
            assert.is_true(W("w")[1])
            drain(9)
            assert.are.same({ false, 0, 0, 0, 0 }, W("w"))
            drain(10) -- still held true: no new edge
            assert.is_false(W("w")[1])
        end)

        it("close_on_false closes on true->false; without it the window stays to its duration", function()
            flagged("a", { close_on_false = true })
            flagged("b", {})
            start()
            on = true
            drain(3)
            on = false
            drain(4)
            assert.is_false(W("a")[1])
            assert.are.same({ true, 3, 9, 0, 0 }, W("b"))
        end)

        it("combat end closes every window, and a condition held through it needs a new edge", function()
            flagged("w", {})
            start()
            ctl.Fire("PLAYER_REGEN_DISABLED")
            on = true
            drain(3)
            assert.is_true(W("w")[1])
            ctl.now = 4
            ctl.Fire("PLAYER_REGEN_ENABLED")
            drain(4.1)
            assert.is_false(W("w")[1])
            drain(5)
            assert.is_false(W("w")[1])
            on = false
            drain(6)
            on = true
            drain(7)
            assert.are.same({ true, 7, 13, 0, 0 }, W("w"))
        end)

        -- Task 8a-5: a function duration's belief side (`now_duration`) runs in the now context at each open and counted
        -- refresh; the forecast's `duration` function is never run here
        it("evaluates now_duration at each open and counted refresh, in the now context", function()
            local len = 2
            flagged("w", {
                refresh = true,
                duration = function()
                    error("the forecast's, never the belief's")
                end,
                now_duration = function()
                    return now > 0 and len or 0 -- luacheck: ignore 113 (the now context)
                end,
            })
            start()
            on = true
            drain(3)
            assert.are.same({ true, 3, 5, 0, 0 }, W("w"))
            on = false
            drain(4)
            len = 4
            on = true
            drain(4.5) -- a counted refresh: the new value
            assert.are.same({ true, 3, 8.5, 1, 0 }, W("w"))
            drain(8.5) -- expired
            on = false
            drain(9)
            len = 1
            on = true
            drain(10) -- a fresh open follows the changed value
            assert.are.same({ true, 10, 11, 0, 0 }, W("w"))
            assert.are.equal(0, I.nowErrors)
        end)

        it("a now_duration that raises or gives no positive number opens nothing; a raise is counted", function()
            local v = "x"
            flagged("w", {
                duration = function()
                    return 1
                end,
                now_duration = function()
                    if v == "x" then
                        error("boom")
                    end
                    return v
                end,
            })
            start()
            local e = I.nowErrors
            on = true
            drain(3)
            assert.are.equal(e + 1, I.nowErrors)
            assert.is_false(W("w")[1])
            for k, bad in ipairs({ 0, -1, "2", false }) do
                v = bad
                on = false
                drain(3 + k)
                on = true
                drain(3.5 + k)
                assert.is_false(W("w")[1], tostring(bad))
            end
            assert.are.equal(e + 1, I.nowErrors)
        end)

        it('"combat" never times out and closes at combat end', function()
            flagged("w", { duration = "combat" })
            start()
            ctl.Fire("PLAYER_REGEN_DISABLED")
            on = true
            drain(3)
            drain(100000)
            assert.is_true(W("w")[1])
            ctl.now = 100001
            ctl.Fire("PLAYER_REGEN_ENABLED")
            drain(100001.1)
            assert.is_false(W("w")[1])
        end)

        it("a raising evaluator counts in I.nowErrors and reads false", function()
            declare("w", {
                duration = 6,
                evaluator = function()
                    error("boom")
                end,
            })
            start()
            local e = I.nowErrors
            drain(3)
            drain(4)
            assert.are.equal(e + 1, I.nowErrors) -- counted once, not every Drain
            assert.is_false(W("w")[1])
        end)

        it("an unknown name answers false, 0, 0, 0, 0", function()
            start()
            assert.are.same({ false, 0, 0, 0, 0 }, W("nope"))
        end)
    end)

    describe("the now verbs", function()
        it(
            "a now() calling openWindow on a real cast opens it at the cast; closeWindow on a closed one is a no-op",
            function()
                declare("w", { duration = 6 })
                register("w_opener", {
                    id = OPENER,
                    now = function()
                        closeWindow("w") -- closed: nothing
                        openWindow("w")
                    end,
                })
                start()
                cast(OPENER, 3)
                assert.are.same({ true, 3, 9, 0, 0 }, W("w"))
                assert.are.equal(0, I.nowErrors)
            end
        )

        it("a cast after the expiry but before its close opens it afresh", function()
            declare("w", { duration = 6, refresh = true })
            register("w_opener", {
                id = OPENER,
                now = function()
                    openWindow("w")
                end,
            })
            start()
            cast(OPENER, 3)
            assert.are.same({ true, 3, 9, 0, 0 }, W("w"))
            ctl.now = 9.1
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", OPENER)
            ctl.Tick(9.15)
            VS.Drain(9.2)
            assert.are.same({ true, 9.1, 15.1, 0, 0 }, W("w"))
        end)

        it("a cast after the expiry but before its close opens it afresh, without refresh too", function()
            declare("w", { duration = 6 })
            register("w_opener", {
                id = OPENER,
                now = function()
                    openWindow("w")
                end,
            })
            start()
            cast(OPENER, 3)
            ctl.now = 9.1 -- the window expired at 9; the fold has not closed it yet
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", OPENER)
            ctl.Tick(9.15)
            VS.Drain(9.2)
            assert.are.same({ true, 9.1, 15.1, 0, 0 }, W("w"))
        end)

        it("are inert outside a cast", function()
            declare("w", { duration = 6 })
            start()
            I.nowCtx.openWindow("w")
            assert.is_false(W("w")[1])
        end)
    end)

    describe("the evaluator's reads", function()
        it("usable.<key> is the last plain IsSpellUsable answer; a secret one keeps it and raises nothing", function()
            local seen
            declare("w", {
                duration = 6,
                close_on_false = true,
                evaluator = function()
                    seen = usable.spender_c
                    return seen
                end,
            })
            start()
            drain(2)
            assert.is_false(seen)
            ctl.usable[fs.SPENDER_C] = { true, false }
            drain(3)
            assert.is_true(seen)
            assert.is_true(W("w")[1])
            ctl.usable[fs.SPENDER_C] = { fake.SECRET, fake.SECRET }
            drain(4)
            assert.is_true(seen)
            assert.is_true(W("w")[1])
            assert.are.equal(0, I.nowErrors)
            ctl.usable[fs.SPENDER_C] = { false, false }
            drain(5)
            assert.is_false(W("w")[1])
        end)

        it("reads now, lastSwing and nextSwing", function()
            local got = {}
            declare("w", {
                duration = 6,
                evaluator = function()
                    got[1], got[2], got[3] = now, lastSwing(1), nextSwing(1)
                    return false
                end,
            })
            start()
            drain(3)
            assert.are.same({ 3, VS.LastSwing(1), VS.Swing(1, 3).est }, got)
            assert.are.equal(0, I.nowErrors)
        end)
    end)

    describe("steps", function()
        local on
        local function stepped(t)
            on = false
            t.evaluator = function()
                return on
            end
            t.duration = 30
            t.steps = { "w_one", "w_two", "w_three" }
            declare("w", t)
        end
        local function open(t)
            on = true
            drain(t)
        end

        it("advances on the due step's cast only, and closes after the last", function()
            stepped({})
            start()
            open(2)
            assert.are.equal(1, W("w")[5])
            cast(ONE, 3)
            assert.are.equal(2, W("w")[5])
            cast(OTHER, 4)
            assert.are.equal(2, W("w")[5])
            cast(TWO, 5)
            assert.are.equal(3, W("w")[5])
            cast(THREE, 6)
            assert.are.same({ false, 0, 0, 0, 0 }, W("w"))
        end)

        it("with loop, returns to step 1 after the last", function()
            stepped({ loop = true })
            start()
            open(2)
            cast(ONE, 3)
            cast(TWO, 4)
            cast(THREE, 5)
            assert.are.same({ true, 1 }, { W("w")[1], W("w")[5] })
        end)

        it(
            'on_deviation "stay": a cast of step 2 on step 1 leaves step 1, and the stalled sequence ends at its duration',
            function()
                stepped({})
                start()
                open(2)
                cast(TWO, 3)
                assert.are.same({ true, 1 }, { W("w")[1], W("w")[5] })
                drain(31.99)
                assert.is_true(W("w")[1])
                drain(32)
                assert.is_false(W("w")[1])
            end
        )

        it('on_deviation "skip": a cast of step 2 on step 1 moves to step 3', function()
            stepped({ on_deviation = "skip" })
            start()
            open(2)
            cast(TWO, 3)
            assert.are.equal(3, W("w")[5])
        end)

        it('on_deviation "end": closes it, even with loop, and it reopens only on a new edge', function()
            stepped({ on_deviation = "end", loop = true })
            start()
            open(2)
            cast(TWO, 3)
            assert.is_false(W("w")[1])
            drain(4) -- held true
            assert.is_false(W("w")[1])
            on = false
            drain(5)
            open(6)
            assert.are.same({ true, 6, 36, 0, 1 }, W("w"))
        end)

        it("strict: an unrelated on-GCD cast ends it; an off-GCD one does not", function()
            stepped({ strict = true })
            start()
            open(2)
            cast(ONE, 3)
            cast(OFF, 4)
            assert.are.same({ true, 2 }, { W("w")[1], W("w")[5] })
            cast(OTHER, 5)
            assert.is_false(W("w")[1])
        end)

        it("strict: a later step's cast follows on_deviation", function()
            stepped({ strict = true })
            start()
            open(2)
            cast(THREE, 3)
            assert.are.same({ true, 1 }, { W("w")[1], W("w")[5] })
        end)

        it("a non-strict window ignores both", function()
            stepped({})
            start()
            open(2)
            cast(OTHER, 3)
            cast(OFF, 4)
            assert.are.same({ true, 1 }, { W("w")[1], W("w")[5] })
        end)
    end)

    -- window.<name> (Families/Now.lua): the sim's state.window answers (Engine/Sim/State.lua mtWindow) at the context's
    -- time, read-only; an unregistered name reads down
    describe("the window reader", function()
        local on
        before_each(function()
            on = false
            declare("w", {
                duration = 5,
                close_on_false = true,
                evaluator = function()
                    return on
                end,
            })
        end)
        -- the shape of a pack's `usable` gated on a window (Rogue's Riposte)
        local usable = function()
            return window.w.up, "needs the window" -- luacheck: ignore 113 (the now context)
        end
        local function at(f, t)
            local v, ok = I.Eval(f, t)
            assert.is_true(ok, tostring(I.nowError))
            return v
        end

        it("a usable reading window.<name>.up: true inside the open window, false outside and unregistered", function()
            start()
            drain(2)
            assert.is_false(at(usable, 2))
            on = true
            drain(3)
            assert.is_true(at(usable, 3))
            assert.is_true(at(usable, 7.99))
            assert.is_false(at(usable, 8)) -- expired, not yet closed by a Drain: down, as the sim's upAt
            assert.is_false(at(function()
                return window.nope.up -- luacheck: ignore 113
            end, 4))
            on = false
            drain(4) -- close_on_false
            assert.is_false(at(usable, 4))
            assert.are.equal(0, I.nowErrors)
        end)

        it("answers down, remains, elapsed and step as the sim; 0 / true when down or unregistered", function()
            start()
            on = true
            drain(3)
            local got = at(function()
                local r, n = window.w, window.nope -- luacheck: ignore 113
                return { r.up, r.down, r.remains, r.elapsed, r.step, n.up, n.down, n.remains, n.elapsed, n.step }
            end, 4)
            assert.are.same({ true, false, 4, 1, 0, false, true, 0, 0, 0 }, got)
        end)

        it("is read-only: an assignment raises (counted) and changes nothing", function()
            start()
            on = true
            drain(3)
            local e = I.nowErrors
            for _, f in ipairs({
                function()
                    window.w.up = false -- luacheck: ignore 112 113
                end,
                function()
                    window.w.next.w_one = true -- luacheck: ignore 112 113
                end,
                function()
                    window.nope = {} -- luacheck: ignore 112 113
                end,
            }) do
                local _, ok = I.Eval(f, 4)
                assert.is_false(ok)
            end
            assert.are.equal(e + 3, I.nowErrors)
            assert.is_true(at(usable, 4))
            assert.are.same(
                { false, false }, -- a stored `window.nope = {}` would read nil here
                at(function()
                    return { window.w.next.w_one, window.nope.up } -- luacheck: ignore 113
                end, 4)
            )
        end)

        it("allocates nothing reading up, remains, next and an unregistered name", function()
            start()
            on = true
            drain(3)
            local f = function()
                local w = window.w -- luacheck: ignore 113
                return w.up and w.remains > 0 and not w.next.w_one and not window.nope.up -- luacheck: ignore 113
            end
            local bytes = alloc.bytes(function(i)
                I.Eval(f, 3 + i * 0.001)
            end, 1000)
            assert.are.equal(0, bytes)
            assert.is_true(at(f, 4))
        end)
    end)

    describe("the window reader's steps", function()
        it("step and next.<ability key> answer the due step of an up window; false for any other key", function()
            local on = false
            declare("s", {
                duration = 30,
                steps = { "w_one", "w_two" },
                evaluator = function()
                    return on
                end,
            })
            start()
            local f = function()
                local s = window.s -- luacheck: ignore 113
                return { s.step, s.next.w_one, s.next.w_two, s.next.nope }
            end
            drain(2)
            assert.are.same({ 0, false, false, false }, (I.Eval(f, 2)))
            on = true
            drain(3)
            assert.are.same({ 1, true, false, false }, (I.Eval(f, 3)))
            cast(ONE, 4)
            assert.are.same({ 2, false, true, false }, (I.Eval(f, 4.1)))
            assert.are.same({ 0, false, false, false }, (I.Eval(f, 33))) -- expired
        end)
    end)

    it("allocates nothing across 1000 Drains with two windows", function()
        local on = false
        declare("a", {
            duration = function()
                return 0.5
            end,
            now_duration = function()
                return now > 0 and 0.5 or 0 -- luacheck: ignore 113 (the now context)
            end,
            refresh = true,
            evaluator = function()
                return on and usable.spender_c and nextSwing(1) >= 0
            end,
        })
        declare("b", {
            duration = 2,
            close_on_false = true,
            steps = { "w_one", "w_two" },
            loop = true,
            evaluator = function()
                return not on and lastSwing(1) >= 0
            end,
        })
        start()
        ctl.usable[fs.SPENDER_C] = { true, false }
        local t = 2
        local bytes = alloc.bytes(function(i)
            t = t + 0.3
            on = i % 3 ~= 0
            drain(t)
        end, 1000)
        assert.are.equal(0, bytes)
        assert.are.equal(0, I.nowErrors)
    end)
end)
