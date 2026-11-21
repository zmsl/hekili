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
            Fake.tick(2)
            assert.are.equal(v, (h:Exact()), v)
        end
        assert.are.same({ 777, 778 }, lohi(h))
        mana(2000)
        Fake.tick(2)
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
        Fake.tick(2)
        assert.are.same({ 33.5, 100 }, lohi(e))
        assert.are.same({ 301, 2000 }, lohi(p))
        assert.are.same({ 33, 34 }, lohi(s))
        assert.are.same({ 670, 671 }, lohi(h))
        mana(300)
        Fake.tick(2)
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
end)
