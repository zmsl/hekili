-- tests/LibHiddenValues/precision_spec.lua: point precision on player power (the ring of 50 fine bars, a Gray cell
-- code and a parity bar, BandProbe2 0.3.0's mana arm): exact points, the other bars released and answered by
-- comparison, the point step grown to keep every curve within 256 points, max <= 100 as position, lost firings caught.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues point precision", function()
    local Fake, W, lib, MANA

    local function untilLive(h)
        for _ = 1, 30 do
            if h:State() == "live" then
                return
            end
            Fake.tick(1)
        end
        error("never live: " .. tostring(h:State()))
    end

    local function mana(points)
        W.unit.player.power[0] = points / W.unit.player.max[0]
    end

    local function bars()
        local n = 0
        for _, s in ipairs(lib:GetSources()) do
            n = n + s.bars
        end
        return n
    end

    local function watch(spec)
        spec.kind, spec.unit, spec.power = "power", "player", spec.power or MANA
        return lib:Watch("A", spec)
    end

    before_each(function()
        Fake = dofile(FAKE)
        Fake.set("maxpoints", 256) -- the client's measured Step curve limit: every curve must fit
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        MANA = Enum.PowerType.Mana
        mana(1234)
    end)

    after_each(function()
        Fake.restore()
    end)

    it("reads the exact value in points, every point, q EXACT", function()
        local h = watch({ precision = "point" })
        Fake.login()
        untilLive(h)
        assert.are.equal(57, bars()) -- 50 fine + 6 cell bits (41 cells) + parity
        assert.are.same({ 1234, 1 }, { h:Exact() })
        assert.are.same({ 1234, 1235 }, lohi(h))
        assert.are.equal(lib.EXACT, select(4, h:Get()))
        assert.are.same({ 1, 0, 2000 }, { h:Domain() })
        for _, v in ipairs({ 1235, 1236, 1199, 0, 1, 49, 50, 51, 999, 1000, 1999, 2000, 777 }) do
            mana(v)
            Fake.tick(3) -- every change is held until the next frame's decode agrees
            assert.are.equal(v, (h:Exact()), v)
        end
        assert.are.same({ 777, 778 }, lohi(h))
        mana(2000)
        Fake.tick(3)
        assert.are.same({ 2000, 2000 }, lohi(h))
        assert.are.equal(0, select(6, lib:GetStats()))
    end)

    it("releases the source's other bars and answers edges, points and steps by comparison", function()
        local e = watch({ edges = { 20, 33.5 } })
        local p = watch({ points = { 301 } })
        local s = watch({ step = 1 })
        Fake.login()
        untilLive(s)
        assert.are.equal(8 + 2, bars()) -- the position set, 33.5 and 301 (20 is on the grid)
        local h = watch({ precision = "point" })
        Fake.tick(1)
        assert.are.equal(57, bars())
        untilLive(h)
        untilLive(e)
        mana(670) -- 33.5% of 2000
        Fake.tick(3) -- every change is held until the next frame's decode agrees
        assert.are.same({ 33.5, 100 }, lohi(e))
        assert.are.same({ 301, 2000 }, lohi(p))
        assert.are.same({ 33, 34 }, lohi(s))
        assert.are.same({ 670, 671 }, lohi(h))
        mana(300)
        Fake.tick(3)
        assert.are.same({ 0, 301 }, lohi(p))
        assert.are.same({ 15, 16 }, lohi(s))
        h:Release()
        Fake.tick(1)
        assert.are.equal(8 + 2, bars())
        untilLive(p)
        assert.are.same({ 0, 301 }, lohi(p))
    end)

    it("keeps at most 4 maxes of ring and point curves, the ones in use always", function()
        local h = watch({ precision = "point" })
        local p = watch({ edges = { 33.5 }, points = { 301 } })
        Fake.login()
        untilLive(h)
        local function count(t)
            local n = 0
            for _ in pairs(t) do
                n = n + 1
            end
            return n
        end
        for _, M in ipairs({ 2100, 2200, 2300, 2400, 2500, 2600, 2700, 2000 }) do
            W.unit.player.max[0] = M
            Fake.event("UNIT_MAXPOWER", "player")
            untilLive(h)
            assert.is_true(count(lib.rings) <= 4, "rings " .. M)
            assert.is_true(count(lib.ptCurves) <= 4, "point curves " .. M)
            assert.truthy(lib.rings[M])
        end
        h:Release()
        untilLive(p)
        assert.truthy(lib.ptCurves[2000][301])
    end)

    it("builds the ring's curves from their change points only: the same curves as a full scan", function()
        for _, M in ipairs({ 2000, 3175, 3176, 6400, 20000 }) do
            local fast, full = lib.ringFor(M), lib.ringFor(M, true)
            assert.are.equal(#full.curves, #fast.curves)
            for k = 1, #full.curves do
                assert.are.same(full.curves[k].pts, fast.curves[k].pts, M .. " curve " .. k)
            end
        end
    end)

    it("grows the point step until every curve fits 256 points", function()
        W.unit.player.max[0] = 6400
        mana(4000)
        local h = watch({ precision = "point" })
        Fake.login()
        untilLive(h)
        local v, step = h:Exact()
        assert.are.equal(3, step) -- 6400 / 2 = 3200 quanta: 128 steps on a fine bar, one too many
        assert.are.equal(3999, v)
        assert.are.same({ 3999, 4002 }, lohi(h))
        assert.are.equal(lib.BAND, select(4, h:Get()))
        assert.are.same({ 3, 0, 6400 }, { h:Domain() })
        W.unit.player.max[0] = 3175 -- 127 steps: exact to 1
        mana(3100)
        Fake.event("UNIT_MAXPOWER", "player")
        Fake.tick(1)
        untilLive(h)
        assert.are.same({ 3100, 1 }, { h:Exact() })
    end)

    it("is position when the max is 100 or less: no extra bars, exact", function()
        W.unit.player.power[3] = 0.42
        local h = watch({ power = 3, precision = "point" })
        Fake.login()
        untilLive(h)
        assert.are.equal(8, bars())
        assert.are.same({ 42, 1 }, { h:Exact() })
        assert.are.same({ 42, 43 }, lohi(h))
        assert.are.equal(lib.EXACT, select(4, h:Get()))
    end)

    it(
        "keeps the other watches' bars when the client refuses the ring's curves: precision alone is suspended",
        function()
            Fake.set("maxpoints", 150) -- a ring curve at 6400 needs ~170 points, the percent parity curve 201
            W.unit.player.max[0] = 6400
            mana(3000)
            local prec = watch({ precision = "point" })
            local other = watch({ points = { 1000 }, edges = { 25 } }) -- 25% is 1600 points
            local step = watch({ step = 1 })
            Fake.login()
            untilLive(other)
            Fake.tick(1)
            assert.are.same({ 1600, 6400 }, lohi(other))
            assert.are.equal("suspended", (prec:State()))
            assert.is_nil((prec:Exact()))
            assert.is_nil((prec:Get()))
            assert.are.same({ 1, 0, 6400 }, { prec:Domain() }) -- the handle's calls all answer: none raises
            assert.is_true(prec:Latency() > 0)
            assert.is_true(prec:SetPoints({ 500 }))
            assert.are.equal("suspended", (prec:State()))
            assert.are.equal("suspended", (step:State())) -- no curve set gives it a cell either
            assert.are.equal("edges", lib:GetSources()[1].mode)
            mana(1200)
            Fake.tick(2)
            assert.are.same({ 1000, 1600 }, lohi(other))
            prec:Release()
            step:Release()
            Fake.tick(2)
            assert.are.same({ 1000, 1600 }, lohi(other)) -- its bars were never moved
            assert.are.equal(0, select(6, lib:GetStats()))
        end
    )

    it("falls back to the 1% position when only the ring is refused and a step watch is there", function()
        W.unit.player.max[0] = 6400
        mana(3000)
        local prec = watch({ precision = "point" })
        local step = watch({ step = 1 })
        lib.rings[6400] = false -- as when the client refused a ring curve at this max
        Fake.login()
        untilLive(step)
        Fake.tick(1)
        assert.are.same({ 46, 47 }, lohi(step)) -- 3000 of 6400: 46.9%
        assert.are.equal("suspended", (prec:State()))
        assert.are.equal("gray", lib:GetSources()[1].mode)
    end)

    it("catches a lost fine firing: never a wrong value, primes again", function()
        local h = watch({ precision = "point" })
        Fake.login()
        untilLive(h)
        local seen = {}
        h:SetSink(function(_, lo)
            seen[#seen + 1] = lo or "nil"
        end)
        Fake.set("drop", 2) -- 1234 -> 1235 fires two fine bars: one is lost
        mana(1235)
        Fake.tick(4)
        Fake.set("drop", 0)
        assert.are.equal(1, select(6, lib:GetStats()))
        untilLive(h)
        Fake.tick(1)
        assert.are.equal(1235, (h:Exact()))
        for i = 1, #seen do
            assert.is_true(seen[i] == "nil" or seen[i] == 1235, tostring(seen[i]))
        end
    end)

    it("refuses a bad precision, leaves health unproven, and keeps within the pool", function()
        for _, bad in ipairs({ "exact", 5, true }) do
            local x, err = watch({ precision = bad })
            assert.is_nil(x)
            assert.are.equal(lib.ERR.PRECISION_INVALID, err)
        end
        local hh = lib:Watch("A", { kind = "health", unit = "player", precision = "point" })
        assert.are.same({ "unavailable", "unproven" }, { hh:State() })
        Fake.login()
        local edges = {}
        for k = 1, 210 do
            edges[k] = k / 3
        end
        assert.truthy(lib:Watch("A", { kind = "health", unit = "target", edges = edges }))
        local x, err = watch({ precision = "point" }) -- 210 + 57 is over 256
        assert.is_nil(x)
        assert.are.equal(lib.ERR.POOL_LIMIT, err)
    end)

    it("counts the largest ring for a precision watch while no plain max is known (before login)", function()
        W.maxSecret = true
        local edges = {}
        for k = 1, 210 do
            edges[k] = k / 3
        end
        assert.truthy(lib:Watch("A", { kind = "health", unit = "target", edges = edges }))
        local x, err = watch({ precision = "point" }) -- 210 + 57 is over 256 (8 would pass)
        assert.is_nil(x)
        assert.are.equal(lib.ERR.POOL_LIMIT, err)
    end)

    it("counts the position set beside a ring at step 1 too: the max can grow past 3175 later", function()
        W.unit.player.max[0] = 3000
        local edges = {}
        for k = 1, 192 do
            edges[k] = k / 3
        end
        assert.truthy(lib:Watch("A", { kind = "health", unit = "target", edges = edges }))
        Fake.login()
        assert.truthy(watch({ precision = "point" })) -- 192 + 57 fits
        local x, err = watch({ step = 1 }) -- no extra bar at step 1 now, but 8 at 6400: counted
        assert.is_nil(x)
        assert.are.equal(lib.ERR.POOL_LIMIT, err)
    end)

    it("counts every edge and point toward the pool when precision is asked (the step can grow later)", function()
        local edges = {}
        for k = 1, 195 do
            edges[k] = k / 3
        end
        assert.truthy(lib:Watch("A", { kind = "health", unit = "target", edges = edges }))
        Fake.login()
        assert.truthy(watch({ edges = { 20, 30, 40, 50, 60 } })) -- at max 2000 (step 1) answered with no bar
        local x, err = watch({ precision = "point" }) -- 195 + 57 fits; with the 5 edges counted, 257 does not
        assert.is_nil(x)
        assert.are.equal(lib.ERR.POOL_LIMIT, err)
    end)

    -- Review I2 (decision: lhv-stage3-fable-decisions.md): at a point step above 1 a threshold off the quantum grid
    -- falls inside the value's quantum; it keeps its own bar so it stays exact to the point.
    describe("at a point step above 1 (max 6400, step 3)", function()
        before_each(function()
            W.unit.player.max[0] = 6400
            mana(3000)
        end)

        it("answers a point off the quantum grid exactly beside a precision watch", function()
            local p = watch({ points = { 4000 } })
            local h = watch({ precision = "point" })
            Fake.login()
            untilLive(h)
            untilLive(p)
            for _, v in ipairs({ 3998, 3999 }) do
                mana(v)
                Fake.tick(3)
                assert.are.same({ 0, 4000 }, lohi(p), v)
            end
            for _, v in ipairs({ 4000, 4001, 4002 }) do
                mana(v)
                Fake.tick(3)
                assert.are.same({ 4000, 6400 }, lohi(p), v)
            end
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        -- Owner decision (L1624 question 2): a step watch reads one 1% cell, never the two a quantum can straddle
        -- (3966-3968 spans 61% and 62%): the Gray set stays beside the ring while a step is asked.
        for _, snap in ipairs({ "left", "right", "nearest" }) do
            it("reads a step watch as one 1% cell beside the ring, its 8 bars counted (" .. snap .. ")", function()
                Fake.set("snap", snap)
                local s = watch({ step = 1 })
                local h = watch({ precision = "point" })
                Fake.login()
                untilLive(h)
                untilLive(s)
                assert.are.equal(57 + 8, bars())
                for _, v in ipairs({ 3967, 3968, 3966, 3969, 3200, 3199, 6400, 6399, 0, 64, 63, 4000 }) do
                    mana(v)
                    Fake.tick(3)
                    local n = math.floor(100 * v / 6400)
                    assert.are.same({ n, n < 100 and n + 1 or 100 }, lohi(s), v)
                    assert.are.equal(v - v % 3, (h:Exact()), v)
                end
                assert.are.equal(0, select(6, lib:GetStats()))
                s:Release() -- no step asked: the Gray set goes
                untilLive(h)
                assert.are.equal(57, bars())
                assert.are.same({ 3999, 3 }, { h:Exact() })
            end)
        end

        it("reads one cell when the max moves across 3175 and back; no Gray set at step 1", function()
            local s = watch({ step = 1 })
            local h = watch({ precision = "point" })
            Fake.login()
            untilLive(h)
            assert.are.equal(57 + 8, bars())
            W.unit.player.max[0] = 3000 -- step 1: the ring alone gives one cell
            mana(1234)
            Fake.event("UNIT_MAXPOWER", "player")
            untilLive(h)
            untilLive(s)
            assert.are.equal(57, bars())
            Fake.tick(2)
            assert.are.same({ 41, 42 }, lohi(s))
            W.unit.player.max[0] = 6400
            mana(3967)
            Fake.event("UNIT_MAXPOWER", "player")
            untilLive(h)
            untilLive(s)
            Fake.tick(2)
            assert.are.equal(57 + 8, bars())
            assert.are.same({ 61, 62 }, lohi(s))
        end)

        it("holds a frame when the Gray set and the ring disagree, then a desync when it lasts", function()
            mana(3966)
            local s = watch({ step = 1 })
            local h = watch({ precision = "point" })
            Fake.login()
            untilLive(h)
            untilLive(s)
            Fake.tick(2)
            assert.are.same({ 61, 62 }, lohi(s))
            local core, splits = s.src.core, select(8, lib:GetStats())
            local i = core[#core] -- the Gray set's parity bar
            mana(3968) -- the ring's quantum stays (3966-3968), the cell moves to 62: only the Gray set fires
            Fake.tick(1)
            lib.barState[i] = not lib.barState[i] -- the parity firing has not arrived yet
            Fake.tick(1)
            assert.are.same({ 61, 62 }, lohi(s)) -- held
            lib.fire(i)
            Fake.tick(1)
            assert.are.same({ 62, 63 }, lohi(s)) -- the ring's quantum did not change: nothing to confirm
            assert.are.equal(splits + 1, select(8, lib:GetStats()))
            assert.are.equal(0, select(6, lib:GetStats()))
            -- a Gray cell that is not the ring's two frames running: a desync, the source primes again
            for k = 1, 8 do
                lib.fire(core[57 + k]) -- stray firings: cell 107, no cell at all
            end
            Fake.tick(3)
            assert.are.equal(1, select(6, lib:GetStats()))
            untilLive(s)
            Fake.tick(2)
            assert.are.same({ 62, 63 }, lohi(s))
        end)

        it("counts the Gray set inside the pool when a step joins a precision source", function()
            local edges = {}
            for k = 1, 192 do
                edges[k] = k / 3
            end
            assert.truthy(lib:Watch("A", { kind = "health", unit = "target", edges = edges }))
            Fake.login()
            assert.truthy(watch({ precision = "point" })) -- 192 + 57 fits
            local x, err = watch({ step = 1 }) -- with the Gray set, 257 does not
            assert.is_nil(x)
            assert.are.equal(lib.ERR.POOL_LIMIT, err)
        end)

        it("counts a step's Gray set when a precision watch joins it", function()
            local edges = {}
            for k = 1, 192 do
                edges[k] = k / 3
            end
            assert.truthy(lib:Watch("A", { kind = "health", unit = "target", edges = edges }))
            Fake.login()
            assert.truthy(watch({ step = 1 }))
            local x, err = watch({ precision = "point" }) -- 192 + 57 + 8
            assert.is_nil(x)
            assert.are.equal(lib.ERR.POOL_LIMIT, err)
        end)

        it("cuts a precision handle's band with its own off-grid point; Exact stays to the step", function()
            local h = watch({ precision = "point", points = { 4000 } })
            Fake.login()
            untilLive(h)
            mana(3999)
            Fake.tick(3)
            assert.are.same({ 3999, 4000 }, lohi(h))
            assert.are.same({ 3999, 3 }, { h:Exact() })
            mana(4000)
            Fake.tick(3)
            assert.are.same({ 4000, 4002 }, lohi(h))
            assert.are.same({ 3999, 3 }, { h:Exact() })
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        it("answers a percent edge whose cut is off the quantum grid", function()
            local e = watch({ edges = { 62.5 } }) -- cut 4000
            local h = watch({ precision = "point" })
            Fake.login()
            untilLive(h)
            untilLive(e)
            for _, v in ipairs({ 3999, 4000, 4001 }) do
                mana(v)
                Fake.tick(3)
                assert.are.same(v < 4000 and { 0, 62.5 } or { 62.5, 100 }, lohi(e), v)
            end
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        it("counts the kept bars and moves them with the max across 3175", function()
            local p = watch({ points = { 500, 300 } }) -- 500 is off the grid of 3, 300 on it
            local h = watch({ precision = "point" })
            Fake.login()
            untilLive(h)
            untilLive(p)
            assert.are.equal(57 + 1, bars())
            assert.truthy(watch({ points = { 501 } })) -- on the grid: no bar
            Fake.tick(1)
            assert.are.equal(57 + 1, bars())
            assert.are.equal(1, select(3, lib:GetPool()))
            W.unit.player.max[0] = 2239 -- step 1: no bar kept
            mana(400)
            Fake.event("UNIT_MAXPOWER", "player")
            untilLive(h)
            untilLive(p)
            assert.are.equal(57, bars())
            assert.are.equal(0, select(3, lib:GetPool()))
            Fake.tick(2)
            assert.are.same({ 300, 500 }, lohi(p))
            W.unit.player.max[0] = 6400
            mana(499)
            Fake.event("UNIT_MAXPOWER", "player")
            Fake.tick(1)
            assert.are_not.equal("live", (p:State()))
            untilLive(h)
            untilLive(p)
            assert.are.equal(57 + 1, bars())
            Fake.tick(2)
            assert.are.same({ 300, 500 }, lohi(p))
            mana(500)
            Fake.tick(3)
            assert.are.same({ 500, 6400 }, lohi(p))
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        it("holds a frame when a kept bar lands after the ring: a split, never a wrong band", function()
            mana(3998)
            local p = watch({ points = { 4000, 4002 } }) -- 4000 keeps a bar, 4002 is on the grid
            local h = watch({ precision = "point", points = { 4000 } })
            Fake.login()
            untilLive(h)
            untilLive(p)
            Fake.tick(2)
            local seen = {}
            p:SetSink(function(_, lo, hi)
                seen[#seen + 1] = { lo, hi }
            end)
            local i = p.src.pbar[4000]
            local splits = select(8, lib:GetStats())
            mana(4005)
            Fake.tick(1) -- every bar fired in this frame
            lib.barState[i] = not lib.barState[i] -- but the kept bar's firing has not arrived yet
            Fake.tick(1) -- the ring says 4005, the bar below 4000: hold
            assert.are.same({ 0, 4000 }, lohi(p))
            assert.are.same({ 3996, 3999 }, lohi(h))
            lib.fire(i) -- the late firing
            Fake.tick(1)
            assert.are.same({ 0, 4000 }, lohi(p)) -- the first valid decode after a bad frame is held too (review I1)
            Fake.tick(1)
            assert.are.same({ 4002, 6400 }, lohi(p))
            assert.are.same({ 4005, 4008 }, lohi(h))
            assert.are.same({ { 4002, 6400 } }, seen)
            assert.are.equal(splits + 1, select(8, lib:GetStats()))
            assert.are.equal(0, select(6, lib:GetStats()))
        end)
    end)

    -- Review I3 (decision: lhv-stage3-fable-decisions.md): a one-step change across a cell boundary (every 50 quanta)
    -- toggles 2 fine bars, a cell bit and the parity bar; half of them alone is a valid state 50 quanta off. The
    -- stagger knob cannot split one change that way: the bar states are set by hand, as the review's R5 did.
    describe("a change across a ring cell boundary", function()
        local h, seen

        local function start(v)
            mana(v)
            h = watch({ precision = "point" })
            Fake.login()
            untilLive(h)
            Fake.tick(2)
            seen = {}
            h:SetSink(function(_, lo)
                seen[#seen + 1] = lo or "nil"
            end)
        end

        -- Moves the mana to v with one half of the change's core firings (late: "fine", the ring's bars, or "cell",
        -- the cell code and parity) not arrived yet; returns those bars.
        local function half(v, late)
            local s, st = h.src, lib.barState
            local before = {}
            for k = 1, #s.core do
                before[k] = st[s.core[k]]
            end
            mana(v)
            Fake.tick(1)
            local held = {}
            for k = 1, #s.core do
                local i = s.core[k]
                if st[i] ~= before[k] and (k <= lib.RING_N) == (late == "fine") then
                    st[i] = not st[i]
                    held[#held + 1] = i
                end
            end
            return held
        end

        -- A half-landed move to v: one frame holds the old value (the sink not called), then v; one split, no desync.
        local function crossing(v, late)
            local old, g = h:Exact()
            local splits, desyncs = select(8, lib:GetStats()), select(6, lib:GetStats())
            seen = {}
            local held = half(v, late)
            assert.is_true(#held >= 2)
            Fake.tick(1)
            assert.are.equal(old, (h:Exact()))
            assert.are.equal(old, (h:Get()))
            assert.are.same({}, seen)
            assert.are.equal(0, h.src.bad) -- a hold is not a bad frame
            for k = 1, #held do
                lib.fire(held[k])
            end
            Fake.tick(1)
            assert.are.same({}, seen) -- the decode moved to v: held until the next frame agrees
            Fake.tick(1)
            assert.are.equal(v - v % g, (h:Exact()))
            assert.are.same({ v - v % g }, seen)
            assert.are.equal(splits + 1, select(8, lib:GetStats()))
            assert.are.equal(desyncs, select(6, lib:GetStats()))
        end

        -- Frames from setting the mana to v until Exact() reads it, with no firing but the client's own.
        local function frames(v)
            mana(v)
            for n = 1, 10 do
                Fake.tick(1)
                if h:Exact() == v then
                    return n
                end
            end
            error("never " .. v)
        end

        it("never shows a value 50 off when half of a one-step change has landed, in either order", function()
            start(1249)
            crossing(1250, "cell") -- the fine pair first: alone it reads 1200
            crossing(1249, "cell") -- alone: 1299
            crossing(1250, "fine") -- the cell pair first: 1299
            crossing(1249, "fine") -- 1200
        end)

        -- Regen moves 2-3 points per change (the owner's run): half of such a change across a boundary, the ring's bars
        -- landed without the cell's, read 50 off before (a scratch run with firings 1-2 frames late: 401 for 451).
        it("never shows a value 50 off when the ring of a 2- to 4-point change lands without its cell", function()
            start(1248)
            crossing(1250, "cell") -- +2: alone the ring reads 1200
            crossing(1247, "cell") -- -3: alone 1297
            crossing(1251, "fine") -- +4: alone the cell pair reads 1297
            crossing(1248, "cell") -- -3: alone 1298
        end)

        it("holds every change one frame until the next decode agrees: jumps of any size alike", function()
            start(1234)
            local F = frames(1235)
            assert.are.equal(3, F) -- the push's frame, the decode held, the next decode agrees
            assert.are.equal(F, frames(1282)) -- +47
            assert.are.equal(F, frames(1223)) -- -59
            assert.are.equal(F, frames(1264)) -- +41
            assert.are.equal(F, frames(1206)) -- -58
            assert.are.same({ 1235, 1282, 1223, 1264, 1206 }, seen)
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        it("reads +1, +50, -37, +1 across a boundary, -49, +100 and +300 in the same frames, no split", function()
            start(1234)
            local splits = select(8, lib:GetStats())
            local F = frames(1235)
            assert.are.equal(F, frames(1236)) -- +1 away from a boundary
            assert.are.equal(F, frames(1286)) -- +50
            assert.are.equal(F, frames(1249)) -- -37
            assert.are.equal(F, frames(1250)) -- +1 across a boundary, every bar in one frame
            assert.are.equal(F, frames(1249))
            assert.are.equal(F, frames(1200)) -- -49 from position 49
            assert.are.equal(F, frames(1300)) -- +100
            assert.are.equal(F, frames(1600)) -- +300
            assert.are.same({ 1235, 1236, 1286, 1249, 1250, 1249, 1200, 1300, 1600 }, seen)
            assert.are.equal(splits, select(8, lib:GetStats()))
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        it("keeps a real jump of 50 within h:Latency() when its firings also split", function()
            start(1234)
            Fake.set("stagger", 2) -- a jump of 50 fires a cell bit and the parity bar: one of the two a frame late
            local worst = 0
            for _, v in ipairs({ 1284, 1234, 1284, 1334 }) do
                worst = math.max(worst, frames(v))
            end
            assert.is_true(worst * lib.frameSec <= h:Latency() + 1e-9, "frames " .. worst)
            assert.are.same({ 1284, 1234, 1284, 1334 }, seen)
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        it("holds in quanta at a step above 1 (max 6400, step 3)", function()
            W.unit.player.max[0] = 6400
            start(3749) -- quantum 1249: 3747
            assert.are.equal(3747, (h:Exact()))
            crossing(3750, "cell") -- alone the fine pair reads quantum 1200: 3600
            crossing(3749, "fine") -- alone the cell pair reads quantum 1200 too
        end)

        it("still counts a hold then two invalid frames as one desync", function()
            start(1249)
            half(1250, "cell")
            Fake.tick(1) -- held
            lib.fire(h.src.core[2]) -- a stray firing on one more fine bar: no ring state at all
            Fake.tick(2)
            assert.are.equal(1, select(6, lib:GetStats()))
            untilLive(h)
            Fake.tick(1)
            assert.are.equal(1250, (h:Exact()))
            for k = 1, #seen do
                assert.is_true(seen[k] == "nil" or seen[k] == 1250, tostring(seen[k]))
            end
        end)
    end)

    -- The owner's run (2026-11-21, max 2479 and 2239, ~10 changes/s): 4 desyncs in 2.5 min and 429 splits. Two changes
    -- on adjacent frames, each split over two frames, leave the bars invalid two frames in a row while firings are
    -- still landing; a lost firing leaves them invalid on a frame with no new firing.
    describe("under regen whose firings land over two frames", function()
        local h, seen

        local function start(v)
            mana(v)
            h = watch({ precision = "point" })
            Fake.login()
            untilLive(h)
            Fake.tick(2)
            seen = {}
            h:SetSink(function(_, lo)
                seen[#seen + 1] = lo or "nil"
            end)
        end

        it("holds through two changes on adjacent frames, each split over two frames: no desync", function()
            start(1234)
            Fake.set("stagger", 2) -- each +1 fires a fine pair: one of the two a frame late
            for v = 1235, 1243, 2 do -- +1, +1 on the next frame, then 4 frames without a change
                mana(v)
                Fake.tick(1)
                mana(v + 1)
                Fake.tick(5)
            end
            assert.are.equal(0, select(6, lib:GetStats()))
            assert.are.equal(1244, (h:Exact()))
            for k = 1, #seen do
                assert.is_true(type(seen[k]) == "number" and seen[k] >= 1234 and seen[k] <= 1244, tostring(seen[k]))
            end
        end)

        -- Moves the mana to v with part of the change's core firings not arrived yet ("one": its first changed ring
        -- bar; "cell": its cell code and parity bars; "all"; a set of cell code bits, 1 = bit 0, NB + 1 the parity);
        -- returns those bars, for the caller to fire a frame later.
        local function move(v, late)
            local s, st = h.src, lib.barState
            local before = {}
            for k = 1, #s.core do
                before[k] = st[s.core[k]]
            end
            mana(v)
            Fake.tick(1)
            local out = {}
            for k = 1, #s.core do
                local i = s.core[k]
                local ring = k <= lib.RING_N
                local hold = late == "all" or ring == (late == "one") and not (late == "one" and #out > 0)
                if type(late) == "table" then
                    hold = late[k - lib.RING_N] == true -- the listed cell code bits (1 = bit 0); NB + 1 the parity
                end
                if st[i] ~= before[k] and hold then
                    st[i] = not st[i]
                    out[#out + 1] = i
                end
            end
            return out
        end

        local function fire(bars)
            for k = 1, #bars do
                lib.fire(bars[k])
            end
        end

        -- Every value the sink was given was one the client held (review I1: a bad run ending on a half-landed change
        -- across a cell read 1200, 50 off, when its first valid decode was taken unchecked).
        local function onlyHeld(list)
            local ok = {}
            for k = 1, #list do
                ok[list[k]] = true
            end
            for k = 1, #seen do
                assert.is_true(seen[k] == "nil" or ok[seen[k]] == true, tostring(seen[k]))
            end
        end

        -- Changes on adjacent frames, each with a bar a frame late (the last, onto 1250, its cell bars), so the decode
        -- is bad while firings land. Review I1: the first valid decode after bad frames read 1200, 50 off, the client
        -- never held it (s.qv is stale then: from 1241 the ring moved 9, from 1400 a spend, neither looked suspect).
        -- Review I3: the first call came on frame 5 while h:Latency() said 3; the measured frames are listed (fix round
        -- 2: every change waits for the next decode to agree).
        for _, case in ipairs({
            { 5, 1247, 1248, 1250 },
            { 6, 1246, 1247, 1248, 1250 },
            { 6, 1241, 1244, 1247, 1250 },
            { 5, 1400, 1248, 1250 },
            { 6, 1236, 1237, 1238, 1239 },
            { 7, 1246, 1247, 1248, 1249, 1250 },
        }) do
            local chain = { unpack(case, 2) }
            it("reports only values the client held, within h:Latency(): " .. table.concat(chain, ", "), function()
                start(chain[1])
                local frames, late = 0, nil -- frames from the first change to the first call
                for k = 2, #chain do
                    local l = move(chain[k], chain[k] == 1250 and "cell" or "one")
                    frames = frames + 1
                    if late then
                        fire(late)
                    end
                    late = l
                end
                while #seen == 0 and frames < 12 do
                    Fake.tick(1)
                    frames = frames + 1
                    fire(late)
                    late = {}
                end
                assert.are.equal(case[1], frames)
                assert.is_true(frames * lib.frameSec <= h:Latency() + 1e-9, "frames " .. frames)
                Fake.tick(2)
                onlyHeld(chain)
                assert.are.equal(chain[#chain], seen[#seen])
                assert.are.equal(0, select(6, lib:GetStats()))
            end)
        end

        -- A spend whose cell bars land apart with the ring complete and no bad frame: a valid cell code of another
        -- cell (fake runs with firings 1-2 frames late read 516 for 116 and 1417 for 1467), or, all cell bars late and
        -- the ring moved under half a cell, a small change from the old value (272 for 122). Every change is held
        -- until the next frame's decode agrees.
        for _, case in ipairs({
            { 417, 116, { [3] = true, [4] = true } }, -- cell 8 to 2: only Gray bits 0 and 1 landed reads cell 10
            { 1617, 1467, { [1] = true, [7] = true } }, -- cell 32 to 29: bit 0 and the parity late read cell 28
            { 269, 122, "cell" }, -- cell 5 to 2, the ring 19 to 22: alone it reads 272, three above 269
        }) do
            it("never reports another cell when a spend's cell bars land apart: " .. case[2], function()
                start(case[1])
                local l = move(case[2], case[3])
                assert.is_true(#l > 0)
                Fake.tick(1) -- valid: the ring complete, a cell code half landed
                fire(l)
                Fake.tick(2)
                assert.are.equal(case[2], (h:Exact()))
                onlyHeld({ case[1], case[2] })
                assert.are.equal(0, select(6, lib:GetStats()))
            end)
        end

        -- Re-review R1: a held jump, then a change across a cell whose cell bars land a frame late. The held frame's
        -- decode (1200: the ring at 1250, the cell still 24) was taken unchecked; it is held again until it repeats.
        it("never reports the decode of a held frame unless it repeats: 1300 to 1248, then +2 across 1250", function()
            start(1300)
            mana(1248)
            Fake.tick(1) -- the jump lands whole
            local l = move(1250, "cell") -- decode: 1248 held; +2 lands, its cell bars late
            Fake.tick(1) -- the held frame's decode: 1200
            fire(l)
            Fake.tick(3)
            assert.are.equal(1250, (h:Exact()))
            onlyHeld({ 1300, 1248, 1250 })
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        -- Documented residual (re-review 2 M-R2b): a reversal across a cell on adjacent frames, 1249 -> 1250 -> 1249, the
        -- first push's cell bars a frame late and the second's ring bars a frame late. The first push's late cell
        -- firings cancel the second's cell firings, so the half state (the ring at 1250, the cell still 24: 1200)
        -- repeats on two decodes and is confirmed. It needs two changes to undo each other bar for bar (for mana a
        -- spend and a regen tick); the fake runs never produced it. Should this start failing, update the README.
        it("confirms a half state rebuilt bar for bar by a reversal on the next frame: 1200 (documented)", function()
            start(1249)
            local l1 = move(1250, "cell") -- its cell bars land a frame late
            local s, st = h.src, lib.barState
            local before = {}
            for k = 1, #s.core do
                before[k] = st[s.core[k]]
            end
            mana(1249)
            Fake.tick(1) -- decode: 1200 held; the reversal's firings land
            local l2 = {}
            for k = 1, lib.RING_N do -- its ring bars a frame late
                local i = s.core[k]
                if st[i] ~= before[k] then
                    st[i] = not st[i]
                    l2[#l2 + 1] = i
                end
            end
            fire(l1) -- they cancel the reversal's cell firings
            Fake.tick(1) -- decode: 1200 again, confirmed
            fire(l2)
            Fake.tick(3)
            assert.are.same({ 1200, 1249 }, seen)
            assert.are.equal(0, select(6, lib:GetStats()))
        end)

        -- Re-review 2 I-R2a: a change half-landed as a prime ends (+2 across 1250 on the prime's last push, its cell bars
        -- a frame late) read 1200 as the first decode after the prime and was taken unconfirmed. The first decode after a
        -- prime is held like any change; the first value still comes within h:Latency() of the prime's last push.
        for _, case in ipairs({
            {
                "a re-prime",
                function()
                    lib.reprime(h.src)
                end,
            },
            {
                "a max change",
                function()
                    W.unit.player.max[0] = 2480
                    mana(1248)
                    Fake.event("UNIT_MAXPOWER", "player")
                end,
            },
        }) do
            it("never reports a half-landed change as the first value after " .. case[1], function()
                W.unit.player.max[0] = 2479
                start(1248)
                case[2]()
                local n = 0
                while lib.barPrime[h.src.core[1]] ~= 1 and n < 40 do
                    Fake.tick(1)
                    n = n + 1
                end
                assert.are.equal(1, lib.barPrime[h.src.core[1]])
                local l = move(1250, "cell") -- the prime's last push: +2 across the cell, its cell bars late
                assert.is_true(#l > 0)
                local frames = 1 -- frames from the prime's last push to the first value
                Fake.tick(1)
                frames = frames + 1
                fire(l)
                while type(seen[#seen]) ~= "number" and frames < 12 do
                    Fake.tick(1)
                    frames = frames + 1
                end
                assert.are.equal(4, frames) -- that push, 1200 held, 1250 held, 1250 confirmed
                assert.is_true(frames * lib.frameSec <= h:Latency() + 1e-9, "frames " .. frames)
                Fake.tick(2)
                onlyHeld({ 1248, 1250 })
                assert.are.equal(1250, (h:Exact()))
                assert.are.equal(0, select(6, lib:GetStats()))
            end)
        end

        -- h:Latency() counts from the frame a change's first firing arrives: here every firing of the first change is a
        -- frame late.
        it("calls within h:Latency() of a change's first firing when that change's firings all arrive late", function()
            start(1236)
            local late = move(1237, "all")
            local frames = 0 -- frames from the first firing
            for v = 1238, 1240 do
                local l = move(v, "one")
                frames = frames + 1
                fire(late)
                late = l
            end
            while #seen == 0 and frames < 12 do
                Fake.tick(1)
                frames = frames + 1
                fire(late)
                late = {}
            end
            assert.is_true(frames * lib.frameSec <= h:Latency() + 1e-9, "frames " .. frames)
            Fake.tick(2)
            onlyHeld({ 1236, 1237, 1238, 1239, 1240 })
            assert.are.equal(1240, seen[#seen])
        end)

        it("still catches a lost firing while the value changes every frame", function()
            start(1234)
            mana(1235)
            Fake.tick(1)
            lib.fire(h.src.core[3]) -- a stray firing on a fine bar (as a lost one): no ring state from here on
            local at
            for f = 1, 12 do
                mana(1235 + f)
                Fake.tick(1)
                at = at or (select(6, lib:GetStats()) > 0 and f) or nil
            end
            assert.is_true(at ~= nil and at <= lib.SETTLE + 1, tostring(at)) -- every frame fired: the cap catches it
            for k = 1, #seen do
                assert.is_true(seen[k] == "nil" or seen[k] >= 1234 and seen[k] <= 1247, tostring(seen[k]))
            end
        end)

        -- A minute of regen (+2 or +3 every 5 to 7 frames) and a spend of 60-259 every 1 to 4 s from the max, each
        -- firing 1 or 2 frames late (lag 1, jitter 1: harsher than the run, where about 28% of the changes split). The
        -- spends outrun the regen by about 40 mana/s: the minute sweeps the range from the max down to 36 (70 frames
        -- below 100); review M1: the old model sat below 100 mana for 3124 of its 3600 frames.
        it("keeps exact mana through a minute of regen with every firing 1-2 frames late: no desync", function()
            W.unit.player.max[0] = 2479
            start(2479)
            assert.has_error(function() -- re-review M5: seed 0 would pin the generator (no jitter)
                Fake.set("seed", 0)
            end)
            Fake.set("lag", 1)
            Fake.set("jitter", 1)
            local m, r, nextRegen, nextSpend, hist, low = 2479, 12345, 6, 120, {}, 2479
            local function rnd(n) -- Park-Miller: exact in doubles
                r = r * 16807 % 2147483647
                return math.floor(r / 65536) % n
            end
            local far = {}
            h:SetSink(function(_, lo)
                local a, b = math.huge, -math.huge -- the client's values over the last 8 frames
                for k = math.max(1, #hist - 8), #hist do
                    a, b = math.min(a, hist[k]), math.max(b, hist[k])
                end
                if lo and (lo < a or lo > b) then
                    far[#far + 1] = lo .. " (client " .. a .. "-" .. b .. ")"
                end
            end)
            for _ = 1, 3600 do
                nextRegen, nextSpend = nextRegen - 1, nextSpend - 1
                if nextRegen <= 0 then
                    m, nextRegen = math.min(2479, m + 2 + rnd(2)), 5 + rnd(3)
                end
                if nextSpend <= 0 then
                    m, nextSpend = math.max(0, m - 60 - rnd(200)), 60 + rnd(180)
                end
                mana(m)
                hist[#hist + 1] = m
                low = math.min(low, m)
                Fake.tick(1)
            end
            assert.are.equal(36, low) -- the sweep reached the bottom
            Fake.set("jitter", 0)
            Fake.tick(6)
            assert.are.equal(0, select(6, lib:GetStats()))
            assert.is_true(select(8, lib:GetStats()) > 100) -- splits: held frames, counted
            assert.are.equal(m, (h:Exact()))
            assert.are.same({}, far)
        end)
    end)
end)
