-- tests/LibHiddenValues/empty_spec.lua: the exact-empty health read (minor 9). A health step watch's bottom cell splits
-- into [0, 0] (exactly empty) and (0, 1) by one Step line at 1e-6 with no guard point. MEASURED (in-game run
-- 2026-11-22, plain input): a Step curve resolves 1e-6 at 0. ASSUMED, never measured: the same on the secret
-- path at empty, and predicted = real at 0. The fake client's secret mode proves nothing about the client.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues exact empty", function()
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
        Fake.set("maxpoints", 256)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        calls = {}
        W.unit.target = { health = 1.0 }
    end)

    after_each(function()
        Fake.restore()
    end)

    it("the fake's Step curve matches the in-game run at 0 and 1e-6 (curve (0,1)(0.000001,2))", function()
        local c = _G.C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, 1)
        c:AddPoint(0.000001, 2)
        assert.are.same({ 1, 2, 2 }, { c:Evaluate(0), c:Evaluate(0.000001), c:Evaluate(0.0001) })
    end)

    it(
        "secret path at empty ASSUMED: empty reads [0, 0], 1 HP of 500,000 reads (0, 1), full still [100, 100]",
        function()
            local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
            Fake.login()
            untilLive(h)
            assert.are.same({ 100, 100 }, lohi(h))
            for _, row in ipairs({
                { 0, 0, 0 },
                { 1 / 500000, 0, 1 },
                { 0, 0, 0 },
                { 0.005, 0, 1 },
                { 0.37, 37, 38 },
                { 0, 0, 0 },
                { 1, 100, 100 },
            }) do
                W.unit.target.health = row[1]
                Fake.tick(3)
                assert.are.same({ row[2], row[3] }, lohi(h), row[1])
            end
            assert.are.equal(8, srcBars("health")) -- no bar added for the empty line
            assert.are.equal(0, select(6, lib:GetStats()))
        end
    )

    it("LIMIT: health under max / 1,000,000 reads empty (1 HP of 2,000,000 reads [0, 0])", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target.health = 1 / 2000000
        Fake.tick(3)
        assert.are.same({ 0, 0 }, lohi(h))
        W.unit.target.health = 2 / 1000000
        Fake.tick(3)
        assert.are.same({ 0, 1 }, lohi(h))
    end)

    it("sits at empty with no desync, beside whole and fractional edges on the same source", function()
        W.unit.target.health = 0.3
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        local e = lib:Watch("B", { kind = "health", unit = "target", edges = { 20, 20.5 } })
        Fake.login()
        untilLive(h)
        untilLive(e)
        assert.are.equal(9, srcBars("health")) -- 8 position bars + the fractional edge's bar
        assert.are.same({ 20.5, 100 }, lohi(e))
        W.unit.target.health = 0
        Fake.tick(3)
        assert.are.same({ 0, 0 }, lohi(h))
        assert.are.same({ 0, 20 }, lohi(e)) -- an edges-only watch gets no empty read
        calls = {}
        Fake.tick(60)
        assert.are.same({}, calls)
        assert.are.same({ 0, 0 }, lohi(h))
        assert.are.same({ 0, 0 }, { select(6, lib:GetStats()), select(8, lib:GetStats()) })
        W.unit.target.health = 0.3
        Fake.tick(3)
        assert.are.same({ 30, 31 }, lohi(h))
        assert.are.same({ 20.5, 100 }, lohi(e))
    end)

    it(
        "empty and cell 0 differ in 2 bars (a Gray bit and the parity bar): either one late holds, never another value",
        function()
            W.unit.target.health = 0.005
            local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
            Fake.login()
            untilLive(h)
            Fake.tick(1)
            local s, st = h.src, lib.barState
            local function half(v, k, want)
                local old, before = lohi(h), {}
                for j = 1, #s.core do
                    before[j] = st[s.core[j]]
                end
                W.unit.target.health = v
                Fake.tick(1)
                local changed = {}
                for j = 1, #s.core do
                    if st[s.core[j]] ~= before[j] then
                        changed[#changed + 1] = s.core[j]
                    end
                end
                assert.are.equal(2, #changed)
                local i = changed[k]
                st[i] = not st[i]
                Fake.tick(1)
                assert.are.same(old, lohi(h), v)
                lib.fire(i)
                Fake.tick(1)
                assert.are.same(old, lohi(h), v)
                Fake.tick(1)
                assert.are.same(want, lohi(h), v)
            end
            half(0, 1, { 0, 0 })
            half(0.005, 1, { 0, 1 })
            half(0, 2, { 0, 0 })
            half(0.005, 2, { 0, 1 })
            assert.are.equal(0, select(6, lib:GetStats()))
        end
    )

    it("re-primes when a fractional edge bar reads up while the position reads empty", function()
        W.unit.target.health = 0
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1, edges = { 20.5 } }, sink)
        Fake.login()
        untilLive(h)
        Fake.tick(3)
        assert.are.same({ 0, 0 }, lohi(h))
        local i = h.src.bar[20.5]
        lib.barState[i] = true -- a made-up firing
        h.src.dirty = true
        Fake.tick(4)
        assert.is_true(select(6, lib:GetStats()) >= 1)
        Fake.tick(20)
        assert.are.same({ 0, 0 }, lohi(h))
    end)

    it("leaves power alone: a power step watch at 0 still reads [0, 1)", function()
        W.unit.player.power[3] = 0
        local h = lib:Watch("A", { kind = "power", unit = "player", power = 3, step = 1 }, sink)
        Fake.login()
        untilLive(h)
        Fake.tick(3)
        assert.are.same({ 0, 1 }, lohi(h))
        assert.are.equal(8, srcBars("power"))
    end)

    it("keeps a two-edge health watch at 2 bars", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 35 } })
        Fake.login()
        untilLive(h)
        assert.are.equal(2, srcBars("health"))
    end)

    it("allocates nothing while a health step watch crosses empty", function()
        local n = 0
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1, edges = { 20.5 } }, function()
            n = n + 1
        end)
        Fake.login()
        untilLive(h)
        local seq = { 0, 0, 1 / 500000, 1 / 500000, 0, 0, 0.3, 0.3 }
        local function frame(i)
            W.unit.target.health = seq[i % #seq + 1]
            Fake.tick(1)
        end
        for i = 1, 200 do
            frame(i)
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local b = collectgarbage("count")
        for i = 1, 1000 do
            frame(i)
        end
        local grew = collectgarbage("count") - b
        collectgarbage("restart")
        assert.is_true(n > 200, n)
        assert.is_true(grew < 0.5, grew .. " KB")
        assert.are.equal(0, select(6, lib:GetStats()))
    end)

    it("builds a health position core made by an older minor again after an upgrade, so it reads empty", function()
        W.unit.target.health = 0.3
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        Fake.login()
        untilLive(h)
        local s = h.src
        for k = 1, #s.core do -- minor 8's state: the core fed from the shared position curves, no empty line
            lib.barCurve[s.core[k]] = lib.grayCurves()[k]
        end
        lib.hcurve = nil
        local _, minor = lib:GetVersion()
        Fake.loadLibrary(minor + 1)
        Fake.tick(20)
        W.unit.target.health = 0
        Fake.tick(3)
        assert.are.same({ 0, 0 }, lohi(h))
    end)
end)
