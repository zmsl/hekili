-- tests/LibTimeToDie/hints_spec.lua: the caller hints (numbers only): HintRate (a time-window multiplier) and HintBelow
-- (a health threshold, its factor learned when not given). Private to the owner: each owner's estimate of a unit sees
-- the shared health crossings and its own hints only. Hostile units only (never the player, never a friendly target;
-- a secret answer counts as hostile). Pushed only when the owner's hint changes (a dropped or learned part is kept).
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

    local function row(token, owner)
        owner = owner or "A"
        for _, r in ipairs(ttd:GetStreams()) do
            if r.token == token and r.owner == owner then
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
        h = ttd:Track("A", "target")
        Fake.tick(12)
    end)

    after_each(function()
        local errors = Fake.errors -- what reached the client's error handler (a sink's error, the driver's, an event's)
        Fake.restore()
        assert.are.same({}, errors)
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

    it("a rate hint bends the owner's estimate at once; ReleaseAll clears the owner's hints", function()
        fall(99, 70, 0.5) -- at 70%: about 34.5 s at the base rate
        local now = GetTime()
        near(34.5, h:Get(), 1.5)
        ttd:HintRate("A", 2, now, now + 10) -- 10 s at x2 burns 40%: 30% left at the base rate
        near(24.5, h:Get(), 1)
        ttd:ReleaseAll("A")
        h = ttd:Track("A", "target")
        Fake.tick(2)
        assert.are.equal(1, row("target").rateFactor)
    end)

    it("two owners on one target get their own estimates; one owner's hint never moves the other's", function()
        local b = ttd:Track("B", "target")
        fall(99, 70, 0.5)
        local now = GetTime()
        ttd:HintRate("A", 2, now, now + 10)
        near(24.5, h:Get(), 1)
        near(34.5, b:Get(), 1.5) -- B sees the same crossings, not A's hint
        ttd:HintRate("B", 1.5, now, now + 10) -- 10 s at x1.5 burns 30%: 39% left at the base rate
        near(29.5, b:Get(), 1)
        near(24.5, h:Get(), 1) -- A's estimate does not move
        ttd:HintBelow("B", 50, 3)
        assert.is_nil(row("target").executePct)
        ttd:ReleaseAll("B")
        near(24.5, h:Get(), 1)
        assert.are.equal(2, row("target").rateFactor)
        assert.is_nil(row("target", "B"))
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

    it("hints reach the owner's later streams and survive a target change, and never reach the player", function()
        local t = GetTime()
        ttd:HintRate("A", 1.3, t, t + 40)
        ttd:HintBelow("A", 35, 1.5)
        local p = ttd:Track("A", "player")
        local r = row("player")
        assert.are.same({ 1, nil, 1 }, { r.rateFactor, r.executePct, r.executeFactor })
        W.unit.target = { health = 0.5 }
        Fake.event("PLAYER_TARGET_CHANGED")
        r = row("target")
        assert.are.same({ 1.3, 35, 1.5 }, { r.rateFactor, r.executePct, r.executeFactor })
        ttd:HintRate("A", 2, t, t + 40)
        assert.are.equal(1, row("player").rateFactor)
        p:Release()
    end)

    it("a friendly target gets no hints; a secret answer counts as hostile", function()
        local t = GetTime()
        ttd:HintRate("A", 1.3, t, t + 40)
        ttd:HintBelow("A", 35, 1.5)
        W.unit.target = { health = 0.5, friendly = true }
        Fake.event("PLAYER_TARGET_CHANGED")
        local r = row("target")
        assert.are.same({ 1, nil }, { r.rateFactor, r.executePct })
        ttd:HintRate("A", 2, t, t + 40) -- a new hint while friendly stays off it
        assert.are.equal(1, row("target").rateFactor)
        W.secretAttack = true -- under the dungeon restrictions the answer may be a secret
        W.unit.target = { health = 0.5, friendly = true }
        Fake.event("PLAYER_TARGET_CHANGED")
        r = row("target")
        assert.are.same({ 2, 35, 1.5 }, { r.rateFactor, r.executePct, r.executeFactor })
        W.secretAttack = nil
        local f = ttd:Track("A", "focus") -- other tokens: decided when the stream opens (no focus: not hostile)
        assert.are.equal(1, row("focus").rateFactor)
        f:Release()
    end)

    it("a friendly target in between keeps the learned threshold factor", function()
        ttd:HintBelow("A", 20)
        fall(99, 21, 0.5)
        fall(20, 10, 0.25) -- twice as fast from its crossing on
        near(1.5, row("target").executeFactor, 0.05)
        W.unit.target = { health = 0.5, friendly = true }
        Fake.event("PLAYER_TARGET_CHANGED")
        assert.is_nil(row("target").executePct)
        W.unit.target = { health = 0.5 }
        Fake.event("PLAYER_TARGET_CHANGED")
        local r = row("target")
        assert.are.equal(20, r.executePct)
        near(1.5, r.executeFactor, 0.05)
    end)

    it("a gap between targets is no flip: a dropped rate hint stays dropped over death and no target", function()
        fall(99, 70, 0.5)
        local t = GetTime()
        ttd:HintRate("A", 2, t, t + 40) -- a phantom: the damage does not change
        fall(69, 55, 0.5)
        assert.are.equal(1, row("target").rateFactor)
        W.unit.target.health = 0
        W.unit.target.dead = true
        Fake.event("UNIT_HEALTH", "target")
        Fake.tick(2)
        W.unit.target = nil
        Fake.event("PLAYER_TARGET_CHANGED")
        Fake.tick(2)
        W.unit.target = { health = 0.9 }
        Fake.event("PLAYER_TARGET_CHANGED")
        Fake.tick(12)
        assert.are.equal(1, row("target").rateFactor)
    end)

    it("a declared threshold bends the projection ahead of it", function()
        fall(99, 30, 0.5) -- at 30%: about 14.5 s at the base rate
        near(14.5, h:Get(), 1.5)
        ttd:HintBelow("A", 20, 2) -- 10% at the base rate, then 20% at x2
        near(9.5, h:Get(), 1)
    end)

    it("a learned threshold factor survives the owner's rate hint and the same threshold again", function()
        ttd:HintBelow("A", 20)
        assert.are.equal(1, row("target").executeFactor)
        fall(99, 21, 0.5)
        fall(20, 10, 0.25) -- twice as fast from its crossing on
        near(1.5, row("target").executeFactor, 0.05) -- halfway from 1 toward 2 (the estimator's execLearn)
        local t = GetTime()
        ttd:HintRate("A", 1.3, t, t + 5)
        near(1.5, row("target").executeFactor, 0.05)
        ttd:HintBelow("A", 20)
        near(1.5, row("target").executeFactor, 0.05)
    end)

    it("a contradicted rate hint is dropped; the owner's threshold or that hint again does not revive it", function()
        fall(99, 70, 0.5)
        local t = GetTime()
        ttd:HintRate("A", 2, t, t + 40) -- a phantom: the damage does not change
        fall(69, 55, 0.5)
        local r = row("target")
        assert.are.equal(1, r.rateFactor)
        assert.are.equal(1, r.drops)
        ttd:HintBelow("A", 20)
        assert.are.equal(1, row("target").rateFactor)
        ttd:HintRate("A", 2, t, t + 40)
        assert.are.equal(1, row("target").rateFactor)
    end)
end)
