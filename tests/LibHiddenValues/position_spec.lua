-- tests/LibHiddenValues/position_spec.lua: position (step = 1): the Gray 7 bits + parity set on health and power, the
-- union grid with edges, binary only while a step listener exists, split (hold one frame) and desync (re-prime).
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues position", function()
    local Fake, W, lib, calls

    local function sink(h, lo, hi, dir)
        calls[#calls + 1] = { lo, hi, dir }
    end

    local function untilLive(h)
        for _ = 1, 30 do
            if h:State() == "live" then
                calls = {}
                return
            end
            Fake.tick(1)
        end
        error("never live: " .. tostring(h:State()))
    end

    local function srcBars(kind)
        for _, s in ipairs(lib:GetSources()) do
            if s.kind == kind then
                return s.bars
            end
        end
        return 0
    end

    before_each(function()
        Fake = dofile(FAKE)
        Fake.set("maxpoints", 256) -- the client's measured Step curve limit
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        calls = {}
        W.unit.target = { health = 0.37 }
    end)

    after_each(function()
        Fake.restore()
    end)

    it("gives the 1% cell from 8 bars, any jump in one call one frame later", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        Fake.login()
        untilLive(h)
        assert.are.same({ 37, 38 }, lohi(h))
        assert.are.same({ 1, 0, 100 }, { h:Domain() })
        assert.are.equal(8, srcBars("health"))
        for _, v in ipairs({ 0.38, 0.375, 0.91, 0.05, 0, 1, 0.999, 0.5 }) do
            W.unit.target.health = v
            Fake.tick(2)
            local n = math.floor(v * 100 + 1e-9)
            assert.are.same({ n, math.min(n + 1, 100) }, lohi(h), v)
        end
        W.unit.target.health = 0.62
        Fake.tick(2)
        calls = {}
        W.unit.target.health = 0.13
        Fake.tick(1)
        assert.are.same({}, calls) -- decoded at the start of the next frame
        Fake.tick(1)
        assert.are.same({ { 13, 14, -1 } }, calls)
        assert.are.equal(0, select(6, lib:GetStats()))
    end)

    it("bands mana by position", function()
        W.unit.player.power[0] = 0.555
        local h = lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Mana, step = 1 }, sink)
        Fake.login()
        untilLive(h)
        assert.are.same({ 55, 56 }, lohi(h))
        W.unit.player.power[0] = 0.2
        Fake.tick(2)
        assert.are.same({ { 20, 21, -1 } }, calls)
    end)

    it("serves edges beside a step from the same source: on the 1% grid without a bar", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1, edges = { 20, 33.5 } }, sink)
        local e = lib:Watch("B", { kind = "health", unit = "target", edges = { 20, 50 } })
        Fake.login()
        untilLive(h)
        untilLive(e)
        assert.are.equal(9, srcBars("health")) -- 8 + the bar of 33.5
        assert.are.same({ 37, 38 }, lohi(h))
        assert.are.same({ 20, 50 }, lohi(e))
        W.unit.target.health = 0.336
        Fake.tick(2)
        assert.are.same({ 33.5, 34 }, lohi(h))
        W.unit.target.health = 0.334
        Fake.tick(2)
        assert.are.same({ 33, 33.5 }, lohi(h))
        W.unit.target.health = 0.6
        Fake.tick(2)
        assert.are.same({ 50, 100 }, lohi(e))
        W.unit.target.health = 0.19
        Fake.tick(2)
        assert.are.same({ 0, 20 }, lohi(e))
        assert.are.same({ 19, 20 }, lohi(h))
    end)

    it("runs binary only while a step listener exists", function()
        local e = lib:Watch("B", { kind = "health", unit = "target", edges = { 20, 50 } })
        Fake.login()
        untilLive(e)
        assert.are.equal(2, srcBars("health"))
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        Fake.tick(1)
        assert.are.equal(8, srcBars("health"))
        untilLive(h)
        untilLive(e)
        h:Release()
        Fake.tick(1)
        assert.are.equal(2, srcBars("health"))
        untilLive(e)
        W.unit.target.health = 0.6
        Fake.tick(2)
        assert.are.same({ 50, 100 }, lohi(e))
    end)

    it("reports 100 as a closed cell at the top", function()
        W.unit.target.health = 1
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        Fake.login()
        untilLive(h)
        assert.are.same({ 100, 100 }, lohi(h))
    end)

    it("holds one frame through a split and reports nothing wrong", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        Fake.login()
        untilLive(h)
        Fake.set("stagger", 2) -- every 2nd firing arrives one frame late: one change's firings land in two frames
        for v = 38, 60 do
            W.unit.target.health = v / 100
            Fake.tick(3)
        end
        for i = 1, #calls do
            local c = calls[i]
            assert.are.equal(c[1] + 1, c[2], i)
            assert.is_true(c[1] >= 37 and c[1] <= 60, i)
        end
        assert.are.same({ 60, 61 }, lohi(h))
        assert.is_true(select(8, lib:GetStats()) > 0) -- splits counted
        assert.are.equal(0, select(6, lib:GetStats()))
    end)

    it("re-primes after a desync (two bad frames) and comes back right", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        Fake.login()
        untilLive(h)
        Fake.set("drop", 2) -- 37 -> 38 fires a Gray bar and the parity bar: one of the two is lost
        W.unit.target.health = 0.38
        Fake.tick(4)
        Fake.set("drop", 0)
        assert.are.equal(1, select(6, lib:GetStats()))
        assert.are.same({ { nil, nil, 0 } }, calls) -- unknown while it primes again, never a wrong band
        untilLive(h)
        assert.are.same({ 38, 39 }, lohi(h))
    end)
end)
