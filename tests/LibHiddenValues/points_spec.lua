-- tests/LibHiddenValues/points_spec.lua: exact thresholds in points on player power: cut = points / plain max, shared
-- bars, free on the 1% grid of a position source, caps rejected whole, SetPoints atomic, cuts re-placed on
-- UNIT_MAXPOWER, a secret max keeps the last plain one.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues points", function()
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

    local function mana(points) -- the fake holds fractions: points of the 2000 max
        W.unit.player.power[0] = points / W.unit.player.max[0]
    end

    local function srcBars()
        local n = 0
        for _, s in ipairs(lib:GetSources()) do
            n = n + s.bars
        end
        return n
    end

    local function watch(spec)
        spec.kind, spec.unit, spec.power = "power", "player", MANA
        return lib:Watch("A", spec)
    end

    before_each(function()
        Fake = dofile(FAKE)
        Fake.set("maxpoints", 256)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        MANA = Enum.PowerType.Mana
        mana(400)
    end)

    after_each(function()
        Fake.restore()
    end)

    it("bands in points between the cuts, exact at each point", function()
        local h = watch({ points = { 500, 300 } })
        Fake.login()
        untilLive(h)
        assert.are.same({ 300, 500 }, lohi(h))
        assert.are.same({ nil, 0, 2000 }, { h:Domain() })
        assert.are.equal(2, srcBars())
        for _, c in ipairs({
            { 299, 0, 300 },
            { 300, 300, 500 },
            { 499, 300, 500 },
            { 500, 500, 2000 },
            { 2000, 500, 2000 },
        }) do
            mana(c[1])
            Fake.tick(2)
            assert.are.same({ c[2], c[3] }, lohi(h), c[1])
        end
    end)

    it("shares one bar per point and costs no bar on the 1% grid of a position source", function()
        local a = watch({ points = { 300 } })
        local b = watch({ points = { 300, 310 } })
        Fake.login()
        Fake.tick(1)
        assert.are.equal(2, srcBars())
        local c = watch({ step = 1, points = { 300 } }) -- 300 of 2000 is 15%: on the grid
        Fake.tick(1)
        assert.are.equal(9, srcBars()) -- 8 + the bar of 310
        untilLive(a)
        untilLive(b)
        untilLive(c)
        mana(312)
        Fake.tick(2)
        assert.are.same({ 300, 2000 }, lohi(a))
        assert.are.same({ 310, 2000 }, lohi(b))
        assert.are.same({ 300, 320 }, lohi(c)) -- the 15% cell in points
        mana(299)
        Fake.tick(2)
        assert.are.same({ 0, 300 }, lohi(a))
        assert.are.same({ 280, 300 }, lohi(c))
        c:Release()
        Fake.tick(1)
        assert.are.equal(2, srcBars())
    end)

    it("rejects a request over the caps whole, and over the pool", function()
        local nine = {}
        for k = 1, 9 do
            nine[k] = 100 * k + 1 -- off the 1% grid
        end
        Fake.login()
        local h, err = watch({ points = nine })
        assert.is_nil(h)
        assert.are.equal(lib.ERR.EDGE_LIMIT, err)
        assert.are.equal(0, #lib:GetSources())
        local made, cap, used, total, per = lib:GetPool()
        assert.are.same({ 256, 0, 64, 8 }, { cap, used, total, per })
        assert.is_number(made)
        assert.truthy(watch({ points = { 101, 201, 301, 401, 501, 601, 701, 801 } }))
        h, err = lib:Watch("A", { kind = "power", unit = "player", power = MANA, predicted = false, points = { 7 } })
        assert.truthy(h) -- another source: its own 8
        lib.POINTS_TOTAL = 9
        h, err = lib:Watch("A", { kind = "power", unit = "player", power = 3, points = { 51, 53 } })
        assert.is_nil(h)
        assert.are.equal(lib.ERR.EDGE_LIMIT, err)
        lib.POINTS_TOTAL = 64
        local edges = {}
        for k = 1, 240 do
            edges[k] = k / 3
        end
        assert.truthy(lib:Watch("A", { kind = "health", unit = "player", edges = edges }))
        -- energy (max 100): 11 sits on the 1% grid, but the position set is 8 more bars: 249 + 8 is over the pool
        h, err = lib:Watch("A", { kind = "power", unit = "player", power = 3, step = 1, points = { 11 } })
        assert.is_nil(h)
        assert.are.equal(lib.ERR.POOL_LIMIT, err)
    end)

    it("swaps a handle's points in one step and keeps the old set on a refusal", function()
        local h = watch({ points = { 300 } })
        Fake.login()
        untilLive(h)
        assert.are.same({ 300, 2000 }, lohi(h))
        local many = {}
        for k = 1, 9 do
            many[k] = 100 * k + 1
        end
        assert.are.same({ nil, lib.ERR.EDGE_LIMIT }, { h:SetPoints(many) })
        assert.are.same({ nil, lib.ERR.POINTS_INVALID }, { h:SetPoints({ 1.5 }) })
        assert.are.same({ nil, lib.ERR.POINTS_INVALID }, { h:SetPoints("300") })
        assert.are.same({ 300, 2000 }, lohi(h))
        assert.are.equal(1, srcBars())
        assert.is_true(h:SetPoints({ 450, 350 }))
        untilLive(h)
        assert.are.same({ 350, 450 }, lohi(h))
        assert.are.equal(2, srcBars())
        local pct = lib:Watch("A", { kind = "power", unit = "player", power = MANA, edges = { 20 } })
        assert.are.same({ nil, lib.ERR.POINTS_INVALID }, { pct:SetPoints({ 300 }) }) -- a percent handle stays percent
    end)

    it("re-places the cuts when the max changes, and keeps the last plain max while it is secret", function()
        local h = watch({ points = { 300 } })
        Fake.login()
        untilLive(h)
        assert.are.same({ 300, 2000 }, lohi(h))
        W.unit.player.max[0] = 1000
        mana(250) -- 0.25 of 1000
        Fake.event("UNIT_MAXPOWER", "player")
        Fake.tick(1)
        assert.is_nil((h:Get()))
        untilLive(h)
        assert.are.same({ 0, 300 }, lohi(h))
        assert.are.same({ nil, 0, 1000 }, { h:Domain() })
        W.maxSecret = true
        Fake.event("UNIT_MAXPOWER", "player")
        untilLive(h)
        assert.are.same({ nil, 0, 1000 }, { h:Domain() })
    end)

    it("is unavailable while no plain max was ever read, and refuses bad points", function()
        W.maxSecret = true
        local h = watch({ points = { 300 } })
        Fake.login()
        Fake.tick(12)
        assert.are.same({ "unavailable", "max-unknown" }, { h:State() })
        assert.is_string(lib:GetMessage("max-unknown"))
        for _, bad in ipairs({ true, { 0 }, { -5 }, { 2.5 }, { "300" } }) do
            local x, err = watch({ points = bad })
            assert.is_nil(x)
            assert.are.equal(lib.ERR.POINTS_INVALID, err)
        end
        local x, err = watch({ points = {} })
        assert.is_nil(x)
        assert.are.equal(lib.ERR.EDGES_REQUIRED, err)
    end)
end)
