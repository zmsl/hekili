-- tests/Forever/driver_alloc_spec.lua (audit first wave, Task 2): Hekili.Update run through the real engine frame
-- (Engine/Driver.lua's OnUpdate) as headless Arms. The Driver reuses one coroutine, so a warmed-up Update through it
-- allocates nothing, AddToStack draws only on its pool, every due frame runs exactly one Update body, and the thread
-- is recreated after a snapshot drops it mid-Update or an Update raises.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("Engine/Driver.lua through the engine frame", function()
    local H, f, upd, runs, ran, t

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        f = H.ns.EngineFrame
        upd, runs = H.Hekili.Update, 0
        H.Hekili.Update = function(...)
            runs, ran = runs + 1, coroutine.running()
            return upd(...)
        end
    end)

    after_each(function()
        H.Hekili.Update = upd
    end)

    -- The clock and the timers on, then one due refresh: frames until the Driver finishes the Update it starts.
    local function tick()
        t = t + 0.2
        H.ctl.now = t
        H.RunTimers(t)
        f.refreshTimer = 10
        local frames = 0
        repeat
            f.__scripts.OnUpdate(f, 0.01)
            frames = frames + 1
            assert(frames < 1000, "the Update never finished")
        until not f:IsThreadActive()
    end

    -- Bytes per refresh over n refreshes after warm-up. The collector stays stopped across the window: a GC cycle
    -- completing between two refreshes would free what the next one rebuilds once (the thread's stack, interned
    -- strings, VM buffers: a cost per cycle, not per Update) and land it on one measured refresh. As in
    -- tests/Game/State/helpers/alloc.lua: collect, absorb that rebuild through the measured path itself, then measure.
    -- `during` runs between the absorbing refresh and the window (to install a measuring wrapper).
    local function perUpdate(n, during)
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("stop")
        tick()
        if during then
            during()
        end
        local b = collectgarbage("count")
        for _ = 1, n do
            tick()
        end
        local d = (collectgarbage("count") - b) * 1024 / n
        collectgarbage("restart")
        return d
    end

    it("allocates 0 B per Update after warm-up, AddToStack included, and runs one Update body per refresh", function()
        -- warm-up: 35 refreshes, past the Driver's 30-sample FPS window filling (its array grows to 32 slots)
        for _ = 1, 35 do
            tick()
        end
        assert.are.equal(35, runs)
        local add, stackBytes, stackCalls = H.Hekili.AddToStack, 0, 0
        local bytes = perUpdate(45, function()
            H.Hekili.AddToStack = function(...)
                local b = collectgarbage("count")
                add(...)
                stackBytes, stackCalls = stackBytes + (collectgarbage("count") - b), stackCalls + 1
            end
        end)
        H.Hekili.AddToStack = add
        assert.are.equal(81, runs)
        assert.is_true(stackCalls > 0)
        assert.are.equal(0, stackBytes * 1024)
        assert.are.equal(0, bytes)
        assert.are.same({}, H.errors)
    end)

    it("still sees an allocation of about 100 B per Update", function()
        for _ = 1, 35 do
            tick()
        end
        local sink = {}
        H.Hekili.Update = function(...)
            sink[runs % 2 + 1] = { 1, 2, 3, 4 } -- a table and its 4-slot array: 128 B on 64-bit Lua 5.1
            runs = runs + 1
            return upd(...)
        end
        assert.is_true(perUpdate(45) >= 100)
    end)

    it("starts a fresh thread after a snapshot drops one mid-Update, and never resumes the dropped one", function()
        tick()
        local perf = H.Hekili.Engine.settings.performance
        local budget = perf.frameBudget
        perf.frameBudget = 1e-9 -- yields at every Yield site
        f.refreshTimer = 10
        f.__scripts.OnUpdate(f, 0.01)
        local stale = f.activeThread
        assert.is_true(f:IsThreadActive())
        perf.frameBudget = budget
        H.Hekili.SaveDebugSnapshot = function()
            return false
        end
        H.Hekili:MakeSnapshot()
        assert.is_nil(f.activeThread)
        local out = H.Hekili.Engine.Output.Primary
        local v, n = out.version, runs
        tick()
        assert.are.equal(n + 1, runs)
        assert.are.equal(v + 1, out.version)
        assert.are.equal("suspended", coroutine.status(stale))
        assert.is_truthy(ran) -- the Update ran in a thread, and not the dropped one
        assert.are_not.equal(stale, ran)
    end)

    it("runs the next Update after one raises", function()
        tick()
        local thrown = false
        H.Hekili.Update = function(...)
            runs = runs + 1
            if not thrown then
                thrown = true
                error("TacoDog: injected")
            end
            return upd(...)
        end
        tick()
        assert.is_true(thrown)
        assert.is_true(#H.errors > 0)
        local out = H.Hekili.Engine.Output.Primary
        local v, n = out.version, runs
        tick()
        assert.are.equal(n + 1, runs)
        assert.are.equal(v + 1, out.version)
    end)
end)
