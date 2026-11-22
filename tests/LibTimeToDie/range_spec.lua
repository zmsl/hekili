-- tests/LibTimeToDie/range_spec.lua: the library's own pins on the estimator's range (not lifted from the lab): the
-- crossing-noise term widens lo as well as hi, and it grows as the death nears (its 1 / left part). The module is
-- loaded alone, as estimator_spec loads it.
local PATH = "src/LibTimeToDie/Estimator.lua"

describe("LibTimeToDie estimator range", function()
    local E

    setup(function()
        local saved = rawget(_G, "LibStub")
        rawset(_G, "LibStub", nil)
        local ok, mod = pcall(dofile, PATH)
        rawset(_G, "LibStub", saved)
        assert(ok, mod)
        E = mod
    end)

    -- Lumpy damage (1, 1, 2 and 6% steps every 0.6 s) from full to `last`: the fits agree, so only the noise term widens.
    local function lumpyTo(opts, last)
        local e = E.New(opts)
        e:Band(0, 100, 100)
        local steps, p, t, k = { 1, 1, 2, 6 }, 100, 0, 0
        while p > last do
            k, t = k + 1, t + 0.6
            p = p - steps[(k - 1) % 4 + 1]
            e:Band(t, p - 1, p)
        end
        return e, t + 0.01
    end

    it("the noise term widens lo below the estimate as well as hi above it, more as the death nears", function()
        for _, last in ipairs({ 40, 20, 8 }) do
            local e, now = lumpyTo(nil, last)
            local est, lo, hi, state = e:Get(now)
            assert.are.equal("fit", state)
            local left = e.pLast - e.deathPct
            local k = math.min(e.rangeMax, math.exp(e.rangeZ * math.sqrt(e.dVar / math.max(1, left))))
            assert.is_true(k > 1.25, "k " .. k) -- the 1 / left part alone is a real widening here
            assert.is_true(lo <= est / k * 1.0001, string.format("last %d: lo %.3f est %.3f k %.3f", last, lo, est, k))
            assert.is_true(hi >= est * k * 0.9999, string.format("last %d: hi %.3f est %.3f k %.3f", last, hi, est, k))
        end
    end)

    it("without the noise term the same lumpy stream has a narrow range", function()
        local e, now = lumpyTo({ rangeZ = 0 }, 8)
        local est, lo, hi = e:Get(now)
        assert.is_true(hi / est < 1.2 and est / lo < 1.2, string.format("%.3f [%.3f, %.3f]", est, lo, hi))
    end)
end)
