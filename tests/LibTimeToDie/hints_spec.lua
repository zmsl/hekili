-- tests/LibTimeToDie/hints_spec.lua: the caller hints (numbers only): HintRate (a time-window multiplier) and HintBelow
-- (a health threshold, its factor learned when not given); global across streams, owner-scoped, several owners
-- multiply, pushed to a stream only when the combined hint changes (a dropped or learned one is not undone by another
-- owner's unrelated call).
local FAKE = "src/LibTimeToDie/Testing/FakeClient.lua"

describe("LibTimeToDie hints", function()
    local Fake, W, ttd, h

    local function to(p)
        W.unit.target.health = (p - 0.5) / 100
    end

    local function fall(from, last, sec)
        for p = from, last, -1 do
            to(p)
            Fake.advance(sec)
        end
    end

    local function row(token)
        for _, r in ipairs(ttd:GetStreams()) do
            if r.token == token then
                return r
            end
        end
    end

    local function near(want, got, tol)
        assert.is_true(got ~= nil and math.abs(got - want) < tol, tostring(got) .. " vs " .. want)
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        W.unit.target = { health = 1.0 }
        ttd = LibStub("LibTimeToDie-1.0")
        assert.is_true(Fake.login())
        h = ttd:Track("T", "target")
        Fake.tick(12)
    end)

    after_each(function()
        Fake.restore()
    end)

    it("refuses bad hints with codes; a nil factor or 1 clears a rate hint, a nil percent a threshold", function()
        local E, t = ttd.ERR, GetTime()
        assert.are.same({ nil, E.OWNER_INVALID }, { ttd:HintRate(1, 2, t) })
        assert.are.same({ nil, E.FACTOR_INVALID }, { ttd:HintRate("A", -1, t) })
        assert.are.same({ nil, E.FACTOR_INVALID }, { ttd:HintRate("A", "x", t) })
        assert.are.same({ nil, E.FACTOR_INVALID }, { ttd:HintRate("A", math.huge, t) })
        assert.are.same({ nil, E.TIME_INVALID }, { ttd:HintRate("A", 2) })
        assert.are.same({ nil, E.TIME_INVALID }, { ttd:HintRate("A", 2, t, t - 1) })
        assert.are.same({ nil, E.TIME_INVALID }, { ttd:HintRate("A", 2, t, "x") })
        assert.are.same({ nil, E.OWNER_INVALID }, { ttd:HintBelow(nil, 20) })
        assert.are.same({ nil, E.PCT_INVALID }, { ttd:HintBelow("A", 0) })
        assert.are.same({ nil, E.PCT_INVALID }, { ttd:HintBelow("A", 101) })
        assert.are.same({ nil, E.PCT_INVALID }, { ttd:HintBelow("A", "x") })
        assert.are.same({ nil, E.FACTOR_INVALID }, { ttd:HintBelow("A", 20, 0) })
        assert.is_true(ttd:HintRate("A", 2, t, t + 10))
        assert.are.equal(2, row("target").rateFactor)
        assert.is_true(ttd:HintRate("A", nil))
        assert.are.equal(1, row("target").rateFactor)
        assert.is_true(ttd:HintBelow("A", 20))
        assert.are.equal(20, row("target").executePct)
        assert.is_true(ttd:HintBelow("A", nil))
        assert.is_nil(row("target").executePct)
    end)

    it("a rate hint bends the estimate at once; several owners multiply; ReleaseAll takes one owner's away", function()
        fall(99, 70, 0.5) -- at 70%: about 34.5 s at the base rate
        local now = GetTime()
        near(34.5, h:Get(), 1.5)
        ttd:HintRate("A", 2, now, now + 10) -- 10 s at x2 burns 40%: 30% left at the base rate
        near(24.5, h:Get(), 1)
        ttd:HintRate("B", 1.5, now, now + 10) -- x3 for 10 s: 60%, then 10%
        near(14.5, h:Get(), 1)
        ttd:ReleaseAll("A")
        near(29.5, h:Get(), 1) -- x1.5 only: 30%, then 40%
        assert.are.equal(1.5, row("target").rateFactor)
    end)

    it("re-issued with the same start and the real end, a rate hint ends early", function()
        local t = GetTime()
        ttd:HintRate("A", 2, t, t + 10)
        ttd:HintRate("A", 2, t, t + 2)
        local r = row("target")
        assert.are.same({ 2, t, t + 2 }, { r.rateFactor, r.rateStart, r.rateEnd })
        ttd:HintRate("A", 2, t) -- open-ended
        assert.is_nil(row("target").rateEnd)
    end)

    it("hints reach streams made later and survive a target change", function()
        local t = GetTime()
        ttd:HintRate("A", 1.3, t, t + 40)
        ttd:HintBelow("A", 35, 1.5)
        local p = ttd:Track("B", "player")
        local r = row("player")
        assert.are.same({ 1.3, 35, 1.5 }, { r.rateFactor, r.executePct, r.executeFactor })
        W.unit.target = { health = 0.5 }
        Fake.event("PLAYER_TARGET_CHANGED")
        r = row("target")
        assert.are.same({ 1.3, 35, 1.5 }, { r.rateFactor, r.executePct, r.executeFactor })
        p:Release()
    end)

    it("a declared threshold bends the projection ahead of it", function()
        fall(99, 30, 0.5) -- at 30%: about 14.5 s at the base rate
        near(14.5, h:Get(), 1.5)
        ttd:HintBelow("A", 20, 2) -- 10% at the base rate, then 20% at x2
        near(9.5, h:Get(), 1)
    end)

    it("without a factor the threshold learns it from the stream; another owner's rate hint leaves it", function()
        ttd:HintBelow("A", 20)
        assert.are.equal(1, row("target").executeFactor)
        fall(99, 21, 0.5)
        fall(20, 10, 0.25) -- twice as fast from its crossing on
        near(1.5, row("target").executeFactor, 0.05) -- halfway from 1 toward 2 (the estimator's execLearn)
        local t = GetTime()
        ttd:HintRate("B", 1.3, t, t + 5)
        near(1.5, row("target").executeFactor, 0.05)
    end)

    it("a rate hint the data contradicts is dropped, and another owner's unrelated call does not revive it", function()
        fall(99, 70, 0.5)
        local t = GetTime()
        ttd:HintRate("A", 2, t, t + 40) -- a phantom: the damage does not change
        fall(69, 55, 0.5)
        local r = row("target")
        assert.are.equal(1, r.rateFactor)
        assert.are.equal(1, r.drops)
        ttd:HintBelow("B", 20)
        assert.are.equal(1, row("target").rateFactor)
    end)
end)
