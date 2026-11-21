-- tests/LibTimeToDie/estimator_spec.lua: the estimator's own checks, lifted with it from the TTD lab (branch ttd-lab
-- f29c14916, tools/ttd_lab/estimator_test.lua: 27 checks), one `it` per check, the asserts unchanged. The module is
-- loaded alone (no LibStub), as the lab ran it, with the library's defaults (staleAnchor 12, the lab's 8).
local PATH = "src/LibTimeToDie/Estimator.lua"

local function loadEstimator()
    local saved = rawget(_G, "LibStub")
    rawset(_G, "LibStub", nil)
    local ok, E = pcall(dofile, PATH)
    rawset(_G, "LibStub", saved)
    assert(ok, E)
    return E
end

-- The lab's seeded Park-Miller generator (tools/ttd_lab/rng.lua), for the fuzz check.
local function newRng(seed)
    local r = { s = (math.floor(seed) % 2147483646) + 1 }
    function r:next()
        self.s = (self.s * 16807) % 2147483647
        return self.s / 2147483647
    end
    function r:uni(a, b)
        return a + (b - a) * self:next()
    end
    return r
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

-- A mob first seen full at 0: n1 crossings at b1 seconds per percent, then n2 at b2.
local function stepped(e, b1, n1, b2, n2)
    e:Band(0, 99, 100)
    local t, p = 0, 100
    for k = 1, n1 + n2 do
        t, p = t + (k <= n1 and b1 or b2), p - 1
        e:Band(t, p - 1, p)
    end
    return t, p
end

describe("LibTimeToDie estimator (the TTD lab's checks)", function()
    local E

    setup(function()
        E = loadEstimator()
    end)

    it("unknown before the first band and at full with no crossing", function()
        local e = E.New()
        assert(e:Get(1) == nil)
        local _, _, _, state = e:Get(1)
        assert(state == "unknown")
        e:Band(1, 99, 100)
        assert(e:Get(2) == nil)
    end)

    it("a mob first seen full answers from its first crossing, with a wide band", function()
        local e = E.New()
        e:Band(10, 99, 100)
        e:Band(10.5, 98, 99) -- 1% in 0.5 s: about 49.5 s to go
        local est, lo, hi, state = e:Get(10.5)
        assert(state == "seed", state)
        assert(math.abs(est - 49.5) < 0.01, est)
        assert(lo < est and hi > est)
    end)

    it("a steady fall converges on the true time to die", function()
        local e = E.New()
        local t, p = steady(e, 0, 100, 0.4, 40) -- health p at t, 0.4 s per percent
        local est, lo, hi, state = e:Get(t)
        assert(state == "fit", state)
        assert(math.abs(est - p * 0.4) < 0.05 * p * 0.4, est)
        assert(lo <= est and est <= hi)
    end)

    it("a mob first seen below full answers from its first crossing, anchored at the first band's middle", function()
        local e = E.New()
        e:Band(0, 59, 60)
        e:Band(1, 58, 59) -- half a percent (59.5 -> 59) in 1 s
        local est, _, _, state = e:Get(1)
        assert(state == "seed", state)
        assert(math.abs(est - 59 * 2) < 0.01, est)
    end)

    it("without that anchor it waits for two percent of crossings", function()
        local e = E.New({ anchorBelow = false })
        e:Band(0, 59, 60)
        e:Band(1, 58, 59)
        assert(e:Get(1) == nil)
        e:Band(2, 57, 58)
        assert(e:Get(2) == nil) -- two crossings, one percent apart
        e:Band(3, 56, 57)
        local est = e:Get(3)
        assert(est and math.abs(est - 57) < 0.01, est) -- 1 s per percent from 57
    end)

    it("the slope carries over a swap: the next mob answers from its first crossing", function()
        local e = E.New()
        local t = steady(e, 0, 100, 0.5, 20)
        assert(e:Get(t))
        e:Restart()
        e:Band(t + 1, 69, 70)
        local est, _, _, state = e:Get(t + 1.1) -- no crossing yet: the carried slope from the band's middle
        assert(state == "prior" and math.abs(est - 69.5 * 0.5) < 0.01, tostring(est))
        e:Band(t + 1.5, 68, 69)
        est = e:Get(t + 1.5)
        assert(est and math.abs(est - 69 * 0.5) < 0.5, tostring(est)) -- the carried slope rules for 8 s; deadband
    end)

    it("with seedWeight 1 a carried slope mixes with the new mob's own anchor slope", function()
        local e = E.New({ seedWeight = 1 })
        local t = steady(e, 0, 100, 0.5, 20) -- 0.5 s per percent
        assert(e:Get(t))
        e:Restart()
        e:Band(t + 1, 99, 100) -- a fresh mob
        e:Band(t + 3, 98, 99) -- its own anchor slope: 2 s per percent
        local est, _, _, state = e:Get(t + 3)
        assert(state == "seed", state)
        assert(math.abs(est - 99 * 1.25) < 0.01, est) -- (0.5 + 2) / 2 seconds per percent
    end)

    it("a carried slope older than priorAge is dropped (a new pull)", function()
        local e = E.New()
        local t = steady(e, 0, 100, 0.5, 20)
        assert(e:Get(t))
        e:Restart()
        e:Band(t + 15, 69, 70)
        assert(e:Get(t + 15.1) == nil)
    end)

    it("without a carried slope a swap onto a damaged mob stays unknown until it has data", function()
        local e = E.New({ prior = false, anchorBelow = false })
        local t = steady(e, 0, 100, 0.5, 20)
        e:Get(t)
        e:Restart()
        e:Band(t + 1, 69, 70)
        e:Band(t + 1.5, 68, 69)
        assert(e:Get(t + 1.5) == nil)
    end)

    it("a heal of 3% restarts the fit but keeps answering", function()
        local e = E.New()
        local t = steady(e, 0, 100, 0.5, 30) -- at 70
        assert(e:Get(t))
        e:Band(t + 0.2, 74, 75) -- healed to 74-75
        local est, _, _, state = e:Get(t + 0.3)
        assert(est and state == "prior", state)
        assert(math.abs(est - 74.5 * 0.5) < 3, est)
    end)

    it("a stall holds the countdown and says so", function()
        local e = E.New()
        local t = steady(e, 0, 100, 0.5, 30) -- at 70, 35 s to go; the stall threshold is max(4, 5 x 0.5) = 4 s
        local at4 = e:Get(t + 4)
        local est, _, _, state = e:Get(t + 10)
        assert(state == "stalled", state)
        assert(math.abs(est - at4) < 0.5, est .. " vs " .. at4)
    end)

    it("with the research's censoring a stall raises the estimate", function()
        local e = E.New({ censor = 1 })
        local t = steady(e, 0, 100, 0.5, 30)
        local before = e:Get(t)
        assert(e:Get(t + 10) > before)
    end)

    it("the deadband holds the published death time: the estimate counts down smoothly", function()
        local e = E.New()
        local t = steady(e, 0, 100, 0.5, 30)
        local a = e:Get(t)
        e:Band(t + 0.45, 68, 69) -- slightly early crossing: a small change
        local b = e:Get(t + 0.45)
        assert(math.abs((a - b) - 0.45) < 1e-9, a - b)
    end)

    it("no division by zero: crossings in the same instant, zero-length streams", function()
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

    it("the default detector follows a speed-up within a few crossings", function()
        local e = E.New()
        local t, p = stepped(e, 0.5, 40, 0.25, 6) -- x2 at 60%
        local est = e:Get(t)
        assert(math.abs(est - p * 0.25) < 0.5, est .. " vs " .. p * 0.25)
        local off = E.New({ detect = 0 })
        stepped(off, 0.5, 40, 0.25, 6)
        assert(off:Get(t) > p * 0.25 * 1.2) -- the time-weighted fit alone still lags
    end)

    it("a rate hint bends the projection ahead of the data; the carried slope stays in base units", function()
        local e = E.New()
        local t = steady(e, 0, 100, 0.5, 30) -- at 70%: 35 s at the base rate
        e:Hint("rate", 2, t, t + 10)
        local est = e:Get(t) -- 10 s at x2 burns 40%, then 30% at the base rate: 25 s
        assert(math.abs(est - 25) < 0.3, est)
        for k = 1, 8 do -- the hinted rate shows up: 0.25 s per percent
            e:Band(t + 0.25 * k, 69 - k, 70 - k)
        end
        e:Get(t + 2)
        e:Restart() -- a swap inside the hint's window
        local now = t + 2.6
        e:Band(now - 0.1, 59, 60)
        est = e:Get(now)
        local inHint = t + 10 - now -- 2 x inHint base seconds burnt at x2, the rest of 59.5 x 0.5 at the base rate
        assert(math.abs(est - (inHint + 59.5 * 0.5 - 2 * inHint)) < 0.3, est)
    end)

    it("the detector drops a rate hint the data contradicts", function()
        local e = E.New()
        local t = steady(e, 0, 100, 0.5, 30)
        e:Hint("rate", 2, t, t + 40) -- a phantom: the damage does not change
        for k = 1, 12 do
            e:Band(t + 0.5 * k, 69 - k, 70 - k)
        end
        assert(e.hf == 1, "hint kept")
        local est = e:Get(t + 6)
        assert(math.abs(est - 58 * 0.5) < 0.1 * 58 * 0.5, est)
    end)

    it("a declared execute bends the projection from its threshold crossing, or ahead (the default)", function()
        local cross = E.New({ detect = 0, execAhead = false })
        cross:Hint("execute", 2, 20)
        local t = steady(cross, 0, 100, 0.5, 70) -- at 30%
        assert(math.abs(cross:Get(t) - 15) < 0.3) -- not yet: 30% at the base rate
        local ahead = E.New({ detect = 0 })
        ahead:Hint("execute", 2, 20)
        steady(ahead, 0, 100, 0.5, 70)
        local est = ahead:Get(t) -- 10% at the base rate, 20% at x2
        assert(math.abs(est - 10) < 0.3, est)
        t = steady(cross, 0, 100, 0.5, 80) -- on to 20% (a fresh stream, same rate)
        for k = 1, 3 do
            cross:Band(t + 0.25 * k, 19 - k, 20 - k)
        end
        est = cross:Get(t + 0.75)
        assert(math.abs(est - 17 * 0.25) < 0.3, est)
    end)

    it("by default a declared execute learns its factor from the streams that cross it", function()
        local e = E.New({ detect = 0 })
        e:Hint("execute", 1, 20) -- the threshold only
        local t = steady(e, 0, 100, 0.5, 80) -- at 20%
        for k = 1, 10 do -- twice as fast below it
            e:Band(t + 0.25 * k, 19 - k, 20 - k)
        end
        assert(math.abs(e:ExecuteFactor() - 1.5) < 0.05, e:ExecuteFactor()) -- halfway from 1 toward 2
        e:Restart()
        assert(math.abs(e.xf - 1.5) < 0.05)
        t = steady(e, 100, 100, 0.5, 70) -- the next mob, at 30%
        local est = e:Get(t) -- 10% at the base rate, 20% at x1.5
        assert(math.abs(est - (5 + 20 * 0.5 / 1.5)) < 0.3, est)
    end)

    it("bad hints clear instead of raising", function()
        local e = E.New()
        for _, h in ipairs({ { 0, 1, 2 }, { -1, 1, 2 }, { 2, 5, 3 }, { nil, 1, 2 }, { 2, nil, 3 } }) do
            e:Hint("rate", 2, 0, 10)
            e:Hint("rate", h[1], h[2], h[3])
            assert(e.hf == 1)
        end
        for _, h in ipairs({ { 2, nil }, { 2, 0 }, { -1, 20 }, { nil, 20 } }) do
            e:Hint("execute", 2, 20)
            e:Hint("execute", h[1], h[2])
            assert(e.xp == 0)
        end
        e:Hint("nonsense", 2, 20)
    end)

    -- LibTimeToDie review I-3: a target idle at full for `idle` s, then 0.5 s per percent (truth about (99 - k) / 2 s).
    local function idleThenFall(e, idle, steps)
        e:Band(0, 99, 100)
        local t
        for k = 1, steps do
            t = idle + 0.5 * (k - 1)
            e:Band(t, 99 - k, 100 - k)
        end
        return t
    end

    it("by default a first band held long before the first crossing does not set the slope", function()
        for k = 1, 6 do -- the same stream, read after k crossings
            local e = E.New()
            local t = idleThenFall(e, 20, k)
            local est, truth = e:Get(t + 0.01), (99 - k) * 0.5
            assert(est == nil or math.abs(est - truth) < 0.3 * truth, k .. ": " .. tostring(est) .. " vs " .. truth)
        end
    end)

    it("by default a clamped fit's range covers the unclamped fit", function()
        local e = E.New({ staleAnchor = 0 }) -- keep the stale anchor: the fit clamps to 0.2 x its cumulative slope
        local t = idleThenFall(e, 20, 5)
        local est, lo, _, state = e:Get(t + 0.01)
        assert(state == "fit" and est > 70, tostring(est) .. " " .. tostring(state))
        assert(lo < 50, "lo " .. tostring(lo)) -- the truth is about 47 s
    end)

    -- TTD lab run 4 (real traces): a pull whose first hit lands in the frame of combat start (LibTimeToDie anchors the
    -- stream there), then 2% every 0.5 s: about 21 s to live after the first chunk.
    it("by default a first hit at the anchor does not read the mob as about to die", function()
        local e = E.New()
        e:Band(10, 100, 100) -- combat start: the library's re-anchor at full (LibHiddenValues' own full band)
        e:Band(10.02, 87, 88) -- a 12% opener chunk one frame later
        local c = 0
        for k = 1, 10 do -- reads 0.3 s .. 3 s later; a crossing of 2% every 0.5 s from 10.52
            local now = 10.02 + 0.3 * k
            while 10.52 + 0.5 * c <= now do
                e:Band(10.52 + 0.5 * c, 85 - 2 * c, 86 - 2 * c)
                c = c + 1
            end
            local est = e:Get(now)
            local truth = 21.5 - 0.3 * k
            assert(est == nil or est > 0.25 * truth, k .. ": est " .. tostring(est) .. " vs about " .. truth)
        end
    end)

    -- Lumpy damage as the owner's first in-game traces show it: 1, 1, 2 and 10% steps every 0.6 s (14% per 2.4 s).
    it("by default the range of a lumpy stream is wide enough to hold its truth", function()
        local e = E.New()
        e:Band(0, 100, 100)
        local steps, p, t, k = { 1, 1, 2, 10 }, 100, 0, 0
        while p > 30 do
            k, t = k + 1, t + 0.6
            p = p - steps[(k - 1) % 4 + 1]
            e:Band(t, p - 1, p)
        end
        local est, lo, hi = e:Get(t + 0.01)
        local truth = p / 14 * 2.4 -- at the mean rate
        assert(
            lo <= truth and truth <= hi,
            string.format("truth %.2f outside [%.2f, %.2f], est %.2f", truth, lo, hi, est)
        )
        assert(hi / lo > 1.5, string.format("hi:lo %.2f", hi / lo))
    end)

    -- A first chunk one frame after the anchor, then 1% per 0.8 s: the noise the range learns from the first crossings
    -- can be huge (the anchor's slope is one hit over no time); the range stays bounded.
    it("the noise range stays within rangeMax of the estimate after a wild first crossing", function()
        local e = E.New({ rangeZ = 1.15, newAnchor = 0 })
        e:Band(0, 100, 100)
        e:Band(0.02, 87, 88)
        local t, p = 0.02, 88
        for _ = 1, 12 do
            t, p = t + 0.8, p - 1
            e:Band(t, p - 1, p)
        end
        local est, lo, hi, state = e:Get(t + 0.01)
        assert(state == "fit", state)
        assert(lo >= est / 3.01 and hi <= est * 3.01, string.format("est %.2f [%.2f, %.2f]", est, lo, hi))
    end)

    it("random streams never return a non-finite or negative estimate", function()
        local rng = newRng(7)
        for i = 1, 300 do
            local e = E.New({
                priorEmpty = rng:next() < 0.5,
                execAhead = rng:next() < 0.5,
                detect = i % 3 * 2.5,
                staleAnchor = i % 4 * 3,
                clampRange = i % 2 == 0,
                newAnchor = i % 3 * 0.1,
                rangeZ = i % 4 * 0.5,
            })
            local t, lo = 0, 99 - math.floor(rng:uni(0, 60))
            if i % 6 == 0 then
                e:Band(t, 100, 100) -- LibHiddenValues' own full band first
            end
            if rng:next() < 0.5 then
                e:Hint("execute", rng:uni(0.5, 3), rng:uni(1, 40))
            end
            e:Band(t, lo, lo + 1)
            for _ = 1, 150 do
                t = t + rng:uni(0, 2)
                local r = rng:next()
                if r < 0.03 then
                    local s = t + rng:uni(-5, 5)
                    e:Hint("rate", rng:uni(0.3, 3), s, rng:next() < 0.3 and nil or s + rng:uni(0, 40))
                elseif r < 0.05 then
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

    it("no allocation in the steady state, with hints and the detector firing", function()
        local e = E.New()
        e:Hint("execute", 1, 20)
        local t = steady(e, 0, 100, 0.5, 10)
        e:Get(t)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        local p = 90
        for k = 1, 5000 do
            t = t + 0.05
            if k == 2000 then
                e:Hint("rate", 1.3, t, t + 40)
            end
            if k % (k % 1000 < 500 and 10 or 4) == 0 then -- the rate steps up and down: the detector cuts
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
end)

-- The library's own default (Estimator.lua's footer, not a lab check): staleAnchor 12 (owner; the lab's 8).
describe("LibTimeToDie estimator (the library's defaults)", function()
    it("drops an anchor older than 12 s at the first crossing, keeps a younger one", function()
        local E = loadEstimator()
        assert.are.equal(12, E.DEFAULTS.staleAnchor)
        local function afterIdle(idle) -- idle at full, then one crossing; the truth is about 49 s
            local e = E.New()
            e:Band(0, 99, 100)
            e:Band(idle, 98, 99)
            return e:Get(idle + 0.01)
        end
        local kept = afterIdle(10) -- the anchor stands: the slope since it is 10 s per percent
        assert.is_true(kept ~= nil and kept > 200, tostring(kept))
        local dropped = afterIdle(14)
        assert.is_true(dropped == nil or dropped < 100, tostring(dropped))
    end)
end)
