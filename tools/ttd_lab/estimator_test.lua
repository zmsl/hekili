-- tools/ttd_lab/estimator_test.lua: the estimator module's own checks, plain Lua 5.1 asserts (it lifts with the
-- module). From the repo root: lua5.1 tools/ttd_lab/estimator_test.lua
package.path = "tools/ttd_lab/?.lua;" .. package.path
local E = require("estimator")

local passed = 0
local function check(name, fn)
    fn()
    passed = passed + 1
    print("ok   " .. name)
end

local function finite(x)
    return x == nil or (x == x and x > -math.huge and x < math.huge)
end

-- A steady stream: first band at `t0` in the cell below `start` (100: the top cell), then one crossing per `dt`.
local function steady(e, t0, start, dt, steps)
    local top = math.min(start, 100)
    e:Band(t0, top - 1, top)
    local t = t0
    for k = 1, steps do
        t = t + dt
        e:Band(t, top - 1 - k, top - k)
    end
    return t, top - steps
end

check("unknown before the first band and at full with no crossing", function()
    local e = E.New()
    assert(e:Get(1) == nil)
    local _, _, _, state = e:Get(1)
    assert(state == "unknown")
    e:Band(1, 99, 100)
    assert(e:Get(2) == nil)
end)

check("a mob first seen full answers from its first crossing, with a wide band", function()
    local e = E.New()
    e:Band(10, 99, 100)
    e:Band(10.5, 98, 99) -- 1% in 0.5 s: about 49.5 s to go
    local est, lo, hi, state = e:Get(10.5)
    assert(state == "seed", state)
    assert(math.abs(est - 49.5) < 0.01, est)
    assert(lo < est and hi > est)
end)

check("a steady fall converges on the true time to die", function()
    local e = E.New()
    local t, p = steady(e, 0, 100, 0.4, 40) -- health p at t, 0.4 s per percent
    local est, lo, hi, state = e:Get(t)
    assert(state == "fit", state)
    assert(math.abs(est - p * 0.4) < 0.05 * p * 0.4, est)
    assert(lo <= est and est <= hi)
end)

check("a mob first seen below full waits for two percent of crossings", function()
    local e = E.New()
    e:Band(0, 59, 60)
    e:Band(1, 58, 59)
    assert(e:Get(1) == nil)
    e:Band(2, 57, 58)
    assert(e:Get(2) == nil) -- two crossings, one percent apart
    e:Band(3, 56, 57)
    local est = e:Get(3)
    assert(est and math.abs(est - 57) < 0.01, est) -- 1 s per percent from 57
end)

check("the slope carries over a swap: the next mob answers from its first crossing", function()
    local e = E.New()
    local t = steady(e, 0, 100, 0.5, 20)
    assert(e:Get(t))
    e:Restart()
    e:Band(t + 1, 69, 70)
    assert(e:Get(t + 1.1) == nil) -- no crossing yet (priorEmpty off)
    e:Band(t + 1.5, 68, 69)
    local est, _, _, state = e:Get(t + 1.5)
    assert(state == "prior" and est and math.abs(est - 69 * 0.5) < 3, tostring(est))
end)

check("without a carried slope a swap onto a damaged mob stays unknown until it has data", function()
    local e = E.New({ prior = false })
    local t = steady(e, 0, 100, 0.5, 20)
    e:Get(t)
    e:Restart()
    e:Band(t + 1, 69, 70)
    e:Band(t + 1.5, 68, 69)
    assert(e:Get(t + 1.5) == nil)
end)

check("a heal of 3% restarts the fit but keeps answering", function()
    local e = E.New()
    local t = steady(e, 0, 100, 0.5, 30) -- at 70
    assert(e:Get(t))
    e:Band(t + 0.2, 74, 75) -- healed to 74-75
    local est, _, _, state = e:Get(t + 0.3)
    assert(est and state == "prior", state)
    assert(math.abs(est - 74.5 * 0.5) < 3, est)
end)

check("a stall raises the estimate and says so", function()
    local e = E.New()
    local t = steady(e, 0, 100, 0.5, 30) -- at 70, 35 s to go
    local before = e:Get(t)
    local est, _, _, state = e:Get(t + 10)
    assert(state == "stalled", state)
    assert(est > before, est)
end)

check("the deadband holds the published death time: the estimate counts down smoothly", function()
    local e = E.New()
    local t = steady(e, 0, 100, 0.5, 30)
    local a = e:Get(t)
    e:Band(t + 0.45, 68, 69) -- slightly early crossing: a small change
    local b = e:Get(t + 0.45)
    assert(math.abs((a - b) - 0.45) < 1e-9, a - b)
end)

check("no division by zero: crossings in the same instant, zero-length streams", function()
    local e = E.New()
    e:Band(5, 99, 100)
    e:Band(5, 95, 96)
    e:Band(5, 90, 91)
    local est, lo, hi = e:Get(5)
    assert(finite(est) and finite(lo) and finite(hi))
    e:Restart()
    e:Band(7, 50, 51)
    e:Band(7, 49, 50)
    e:Band(7, 48, 49)
    est, lo, hi = e:Get(7)
    assert(finite(est) and finite(lo) and finite(hi))
end)

check("random streams never return a non-finite or negative estimate", function()
    local rng = require("rng").new(7)
    for _ = 1, 200 do
        local e = E.New({ priorEmpty = rng:next() < 0.5 })
        local t, lo = 0, 99 - math.floor(rng:uni(0, 60))
        e:Band(t, lo, lo + 1)
        for _ = 1, 150 do
            t = t + rng:uni(0, 2)
            local r = rng:next()
            if r < 0.05 then
                e:Restart()
                lo = math.floor(rng:uni(1, 99))
            elseif r < 0.15 then
                lo = math.min(99, lo + math.floor(rng:uni(1, 6)))
            elseif lo > 0 then
                lo = math.max(0, lo - math.floor(rng:uni(1, 4)))
            end
            e:Band(t, lo, lo + 1)
            local est, l, h = e:Get(t + rng:uni(0, 1))
            assert(finite(est) and finite(l) and finite(h))
            assert(est == nil or (est >= 0 and l <= est and est <= h))
        end
    end
end)

check("no allocation in the steady state", function()
    local e = E.New()
    local t = steady(e, 0, 100, 0.5, 10)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local p = 90
    for k = 1, 5000 do
        t = t + 0.05
        if k % 10 == 0 then
            p = p - 1
            if p < 2 then
                e:Restart()
                p = 99
                e:Band(t, p, p + 1)
            else
                e:Band(t, p - 1, p)
            end
        end
        e:Get(t)
    end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    assert(grown < 1, grown .. " KB")
end)

print(passed .. " checks passed")
