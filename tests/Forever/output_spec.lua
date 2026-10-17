-- tests/Forever/output_spec.lua (restructure plan, Task 3): the engine output, src/Hekili/Engine/Output.lua. Pure
-- Begin/Publish/Subscribe/Annotate on the file alone, then stock Hekili headless as Arms: a build suspended at every
-- yield never shows a half-built set, a snapshot during a suspended build drops the stale thread (R1), and the status
-- record bumps on a combat flip only.
local alloc = require("Virtual.State.helpers.alloc")
local headless = require("Virtual.harness.headless")
local ww = require("Forever.helpers.warrior_world")

-- A fresh Output.lua: returns Hekili.Engine (public) and ns.Output (private).
local function load()
    local env = setmetatable({ Hekili = { Engine = {} } }, { __index = _G })
    local f = assert(loadfile("src/Hekili/Engine/Output.lua"))
    setfenv(f, env)
    local ns = {}
    f("Hekili", ns)
    return env.Hekili.Engine, ns.Output
end

-- One build of `n` records into `name`, published.
local function build(Out, name, n)
    local s = Out.Begin(name)
    for i = 1, n do
        s[i].actionName, s[i].time = "a" .. i, i
    end
    Out.Publish(name, n)
end

describe("Engine.Output (pure)", function()
    local Engine, Out
    before_each(function()
        Engine, Out = load()
    end)

    it("is one table behind two handles, with every display and the status record", function()
        assert.are.equal(Out, Engine.Output)
        for _, name in ipairs({ "Interrupts", "Defensives", "Cooldowns", "Primary", "AOE", "status" }) do
            assert.is_table(Out[name], name)
            assert.are.equal(0, Out[name].version)
        end
        assert.is_nil(Engine.Publish)
        assert.is_nil(Engine.Begin)
    end)

    it(
        "Begin hands out scratch (not recs) cleared of its scalars; Publish swaps them and bumps version and count",
        function()
            local o = Out.Primary
            local recs, scratch = o.recs, o.scratch
            scratch[2].stale, scratch[2].belief.lo = 1, 1
            local res = scratch[2].resources
            assert.are.equal(scratch, Out.Begin("Primary"))
            assert.is_nil(scratch[2].stale)
            assert.is_nil(scratch[2].belief.lo)
            assert.are.equal(res, scratch[2].resources)
            scratch[1].actionName = "x"
            Out.Publish("Primary", 1)
            assert.are.equal(scratch, o.recs)
            assert.are.equal(recs, o.scratch)
            assert.are.equal(1, o.version)
            assert.are.equal(1, o.count)
            assert.are.equal("x", o.recs[1].actionName)
            build(Out, "Primary", 0)
            assert.are.equal(2, o.version)
            assert.are.equal(0, o.count)
            assert.are.equal(recs, o.recs)
        end
    )

    it("calls subscribers in order with (name, version, output); Wanted counts only non-passive ones", function()
        local seen = {}
        local function mk(tag)
            return function(name, version, o)
                seen[#seen + 1] = tag .. name .. version .. tostring(o == Out.AOE)
            end
        end
        local a, b, c = mk("a"), mk("b"), mk("c")
        assert.is_false(Out.Wanted("AOE"))
        Engine.Subscribe("AOE", a, true)
        assert.is_false(Out.Wanted("AOE"))
        Engine.Subscribe("AOE", b)
        Engine.Subscribe("AOE", b) -- idempotent
        Engine.Subscribe("AOE", c)
        assert.is_true(Out.Wanted("AOE"))
        build(Out, "AOE", 2)
        assert.are.same({ "aAOE1true", "bAOE1true", "cAOE1true" }, seen)
        Engine.Unsubscribe("AOE", b) -- mid-list
        build(Out, "AOE", 2)
        assert.are.same({ "aAOE1true", "bAOE1true", "cAOE1true", "aAOE2true", "cAOE2true" }, seen)
        Engine.Unsubscribe("AOE", c)
        assert.is_false(Out.Wanted("AOE"))
        Engine.Unsubscribe("AOE", a)
        assert.are.equal(0, Out.AOE.subs.n)
        assert.is_true(Engine.Subscribe("AOE", a))
        assert.is_true(Engine.Subscribe("AOE", b))
        assert.is_true(Engine.Subscribe("AOE", c))
        assert.is_true(Engine.Subscribe("AOE", function() end))
        assert.is_false(Engine.Subscribe("AOE", function() end)) -- four slots
    end)

    it("calls every subscriber once when one unsubscribes itself mid-publish; the next publish skips it", function()
        local calls = { 0, 0, 0 }
        local s2
        local function s1()
            calls[1] = calls[1] + 1
        end
        s2 = function()
            calls[2] = calls[2] + 1
            Engine.Unsubscribe("Primary", s2)
        end
        local function s3()
            calls[3] = calls[3] + 1
        end
        Engine.Subscribe("Primary", s1)
        Engine.Subscribe("Primary", s2)
        Engine.Subscribe("Primary", s3)
        build(Out, "Primary", 1)
        assert.are.same({ 1, 1, 1 }, calls)
        assert.are.equal(2, Out.Primary.subs.n)
        assert.are.equal(2, Out.Primary.wanted)
        build(Out, "Primary", 1)
        assert.are.same({ 2, 1, 2 }, calls)
    end)

    it("re-subscribing with another passive flag updates Wanted", function()
        local function s() end
        Engine.Subscribe("AOE", s, true)
        assert.is_false(Out.Wanted("AOE"))
        Engine.Subscribe("AOE", s)
        assert.is_true(Out.Wanted("AOE"))
        assert.are.equal(1, Out.AOE.subs.n)
        Engine.Subscribe("AOE", s, true)
        assert.is_false(Out.Wanted("AOE"))
        Engine.Unsubscribe("AOE", s)
        assert.are.equal(0, Out.AOE.wanted)
    end)

    it("status is the one record it publishes: count is always 1", function()
        assert.are.equal(1, Out.status.count)
        Out.Publish("status", 1)
        assert.are.equal(1, Out.status.version)
        assert.are.equal(1, Out.status.count)
    end)

    it("allocates nothing over 1000 build rounds with two subscribers", function()
        local n = 0
        local function s1()
            n = n + 1
        end
        local function s2()
            n = n + 1
        end
        Engine.Subscribe("Primary", s1)
        Engine.Subscribe("Primary", s2, true)
        local s = Out.Begin("Primary")
        for i = 1, 3 do -- first fill sizes each record's hash part
            s[i].actionName, s[i].time = "a", 1
        end
        local fill = { "a", "b", "c" }
        local bytes = alloc.bytes(function(r)
            local sc = Out.Begin("Primary")
            for i = 1, 3 do
                sc[i].actionName, sc[i].time = fill[i], r
            end
            Out.Publish("Primary", 3)
        end, 1000)
        assert.are.equal(0, bytes)
        assert.is_true(n >= 2000)
    end)

    it("runs annotators over exactly `count` records before subscribers see them, allocation-free", function()
        local calls = 0
        local function ann(name, rec, i)
            calls = calls + 1
            rec.belief.lo = i
        end
        local got
        Engine.Subscribe("Cooldowns", function(_, _, o)
            got = { o.recs[1].belief.lo, o.recs[2].belief.lo, o.recs[3].belief.lo }
        end)
        assert.is_true(Out.Annotate(ann))
        build(Out, "Cooldowns", 2)
        assert.are.equal(2, calls)
        assert.are.same({ 1, 2 }, got)
        Out.Unannotate(ann)
        build(Out, "Cooldowns", 2)
        assert.are.equal(2, calls)
        assert.are.same({}, got)

        Out.Annotate(ann)
        local bytes = alloc.bytes(function()
            Out.Begin("Interrupts")
            Out.Publish("Interrupts", 3)
        end, 1000)
        assert.are.equal(0, bytes)
    end)

    it("Subscribe drops slots blanked by a publish a subscriber error cut short before the 4-slot check", function()
        local s1
        s1 = function()
            Engine.Unsubscribe("AOE", s1) -- mid-publish: blanks the slot, compaction waits for the loop's end
        end
        local function s2()
            error("subscriber error")
        end
        Engine.Subscribe("AOE", s1)
        Engine.Subscribe("AOE", s2)
        assert.is_false(pcall(build, Out, "AOE", 1)) -- the raise skips Publish's compaction
        Engine.Unsubscribe("AOE", s2)
        for _ = 1, 4 do
            assert.is_true(Engine.Subscribe("AOE", function() end))
        end
    end)
end)

describe("Engine.Output (headless Arms)", function()
    local H, out, t

    local function boot()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        out = H.Hekili.Engine.Output.Primary
        assert.is_true(out.count >= 3)
    end

    -- The first `n` published names and times, copied.
    local function names(n)
        local q = {}
        for i = 1, n do
            q[#q + 1] = tostring(out.recs[i].actionName) .. "@" .. tostring(out.recs[i].time)
        end
        return q
    end

    -- Every published record holds a complete recommendation.
    local function complete()
        for i = 1, out.count do
            local r = out.recs[i]
            assert.is_table(H.Hekili.Class.abilities[r.actionName], tostring(r.actionName))
            assert.is_number(r.time)
            assert.is_number(r.exact_time)
        end
    end

    -- Update in a coroutine that yields at every Yield site.
    local function suspendable()
        H.Hekili.maxFrameTime, H.Hekili.activeFrameStart = 0.001, -math.huge
        t = t + 0.2
        H.ctl.now = t
        return coroutine.create(H.Hekili.Update)
    end

    before_each(boot)

    it("never shows a half-built set: recs and version hold until the swap, then every record is complete", function()
        assert.are.same({}, H.errors)
        local v0, recs0, before = out.version, out.recs, names(3)
        local co = suspendable()
        local yields, published = 0, false
        while true do
            assert(coroutine.resume(co))
            if coroutine.status(co) == "dead" then
                break
            end
            yields = yields + 1
            if out.version == v0 then
                assert.is_false(published)
                assert.are.equal(recs0, out.recs)
                assert.are.same(before, names(3))
            else
                published = true
                assert.are.equal(v0 + 1, out.version)
                complete()
            end
        end
        H.Hekili.maxFrameTime = 0
        assert.is_true(yields > 20, "yields: " .. yields)
        assert.are.equal(v0 + 1, out.version)
        complete()
        assert.are.same({}, H.errors)
    end)

    it("R1: a snapshot during a suspended build drops the stale thread and leaves recs the snapshot's set", function()
        local v0 = out.version
        local co = suspendable()
        H.ns.EngineFrame.activeThread = co
        repeat
            assert(coroutine.resume(co))
        until H.Hekili.State.display == "Primary" or coroutine.status(co) == "dead"
        assert.are.equal("suspended", coroutine.status(co))
        assert.are.equal(v0, out.version)
        H.Hekili.maxFrameTime = 0
        -- the snapshot's report (GenerateProfile) trips on a harness talent stub; the run and the thread drop are the point
        H.Hekili.SaveDebugSnapshot = function()
            return false
        end
        H.Hekili:MakeSnapshot()
        assert.is_nil(H.ns.EngineFrame.activeThread)
        assert.are.equal(v0 + 1, out.version)
        local recs, after = out.recs, names(out.count)
        complete()
        -- one engine frame tick (before its refresh is due): the stale thread is not resumed, recs stay the snapshot's
        local f = H.ns.EngineFrame
        f.refreshTimer = 0
        f.__scripts.OnUpdate(f, 0.01)
        assert.is_nil(f.activeThread)
        assert.are.equal("suspended", coroutine.status(co))
        assert.are.equal(v0 + 1, out.version)
        assert.are.equal(recs, out.recs)
        assert.are.same(after, names(out.count))
    end)

    it("bumps the status version on a combat flip and not otherwise", function()
        local st = H.Hekili.Engine.Output.status
        assert.are.equal(ww.SPEC, st.specID)
        assert.is_false(st.combat)
        local v = st.version
        assert.is_true(v >= 1)
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.equal(v, st.version)
        H.Fire("PLAYER_REGEN_DISABLED")
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.is_true(st.combat)
        assert.are.equal(v + 1, st.version)
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.equal(v + 1, st.version)
    end)

    it(
        "WeakAuras: a passive subscriber from PLAYER_ENTERING_WORLD fills payload and scans the six arguments",
        function()
            local calls = {}
            H.env.WeakAuras = {
                ScanEvents = function(...)
                    calls[#calls + 1] = { n = select("#", ...), ... }
                end,
            }
            local wanted = H.ns.Output.Wanted("Primary")
            H.Fire("PLAYER_ENTERING_WORLD", false, false)
            assert.are.equal(wanted, H.ns.Output.Wanted("Primary")) -- passive
            t = t + 0.2
            assert(headless.cycle(H, t))
            local c
            for _, call in ipairs(calls) do
                if call[2] == "Primary" then
                    c = call
                end
            end
            assert.is_table(c, "no Primary scan")
            local p = out.payload
            assert.are.equal(6, c.n)
            assert.are.equal("HEKILI_RECOMMENDATION_UPDATE", c[1])
            assert.are.equal(out.recs[1].actionID, c[3])
            assert.are.equal(out.recs[1].indicator, c[4])
            assert.is_nil(c[5])
            assert.are.equal(p, c[6])
            assert.are.equal(out.recs[1].actionName, p[1].actionName)
            assert.are.equal(out.recs[2].actionName, p[2].actionName)
            assert.are_not.equal(out.recs[1], p[1])
            assert.are.equal(p[1].actionName, p.actionName) -- the stock __index = payload[1]
            assert.are.equal("kv", getmetatable(p).__mode)
            assert.are.same({}, H.errors)
            assert.are.same({}, headless.unexpected(H, "run"))
        end
    )
end)
