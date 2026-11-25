-- tests/LibHiddenValues/plates_spec.lua: nameplate tokens (minor 10). Health on nameplate1-40, the 5% step (a 5-bit
-- Gray code of the cell 0-20 + parity: 6 bars; cell 20 is exactly 100), and NAME_PLATE_UNIT_ADDED / REMOVED: a token
-- can name another mob at once. MEASURED (an in-game probe): plate health decodes through bars, the 5% set
-- held 0 splits and 0 desyncs, the unit argument of both events is plain. The fake client proves nothing about the client.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues nameplates", function()
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

    local function srcBars(unit)
        for _, s in ipairs(lib:GetSources()) do
            if s.unit == unit then
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
    end)

    after_each(function()
        Fake.restore()
    end)

    it("answers health on nameplate1-40, not nameplate41 or 0", function()
        Fake.login()
        for _, u in ipairs({ "nameplate1", "nameplate7", "nameplate40" }) do
            assert.are.same({ true, "ready" }, { lib:IsAvailable("health", u) }, u)
        end
        for _, u in ipairs({ "nameplate41", "nameplate0" }) do
            assert.are.same({ false, "unavailable", "unproven" }, { lib:IsAvailable("health", u) }, u)
        end
        assert.are.same({ false, "unavailable", "unproven" }, { lib:IsAvailable("power", "nameplate7") })
    end)

    it("grants step 5 as the 5% cell on 6 bars: Domain 5, the top cell exactly 100, 0 reads 0-5", function()
        Fake.plate("nameplate7", { health = 0.37 })
        local h = lib:Watch("A", { kind = "health", unit = "nameplate7", step = 5 }, sink)
        Fake.login()
        untilLive(h)
        assert.are.same({ 5, 0, 100 }, { h:Domain() })
        assert.are.equal(6, srcBars("nameplate7"))
        assert.are.same({ 35, 40 }, lohi(h))
        for _, row in ipairs({
            { 0.38, 35, 40 },
            { 0.4, 40, 45 },
            { 0.999, 95, 100 },
            { 1, 100, 100 },
            { 0.95, 95, 100 },
            { 0.049, 0, 5 },
            { 0, 0, 0 + 5 }, -- the exact-empty read is the 1% step's only
            { 0.05, 5, 10 },
            { 0.62, 60, 65 },
        }) do
            W.unit.nameplate7.health = row[1]
            Fake.tick(3) -- any jump: one call two frames later
            assert.are.same({ row[2], row[3] }, lohi(h), row[1])
        end
        assert.are.same({ 0, 0 }, { select(6, lib:GetStats()), select(8, lib:GetStats()) })
        assert.are.same({ 40, 45, 1 }, calls[1])
        assert.are.equal(7, #calls) -- 0.38 and 0 stayed in their cells
    end)

    it("serves edges beside a 5% step: on the 5% grid without a bar, off it with one", function()
        Fake.plate("nameplate2", { health = 0.5 })
        local h = lib:Watch("A", { kind = "health", unit = "nameplate2", step = 5, edges = { 20, 33 } }, sink)
        local e = lib:Watch("B", { kind = "health", unit = "nameplate2", edges = { 25 } }, sink)
        Fake.login()
        untilLive(h)
        untilLive(e)
        assert.are.equal(7, srcBars("nameplate2")) -- 6 position bars + the bar of 33
        assert.are.same({ 50, 55 }, lohi(h))
        assert.are.same({ 25, 100 }, lohi(e))
        for _, row in ipairs({ { 0.34, 33, 35, 25, 100 }, { 0.32, 30, 33, 25, 100 }, { 0.24, 20, 25, 0, 25 } }) do
            W.unit.nameplate2.health = row[1]
            Fake.tick(3)
            assert.are.same({ row[2], row[3] }, lohi(h), row[1])
            assert.are.same({ row[4], row[5] }, lohi(e), row[1])
        end
        assert.are.equal(0, select(6, lib:GetStats()))
    end)

    it("runs the 1% set for a 1% and a 5% watch on one source: the 5% one answers from the 1% cell", function()
        W.unit.target = { health = 0.37 }
        local fine = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        local five = lib:Watch("B", { kind = "health", unit = "target", step = 5 }, sink)
        Fake.login()
        untilLive(fine)
        untilLive(five)
        assert.are.equal(8, srcBars("target"))
        assert.are.same({ 5, 0, 100 }, { five:Domain() })
        assert.are.same({ 1, 0, 100 }, { fine:Domain() })
        assert.are.same({ 35, 40 }, lohi(five))
        for p = 36, 41 do
            W.unit.target.health = p / 100
            Fake.tick(3)
            assert.are.same({ p, p + 1 }, lohi(fine), p)
        end
        assert.are.same({ { 40, 45, 1 } }, calls) -- fired on its own cell's change only
        for _, row in ipairs({ { 0, 0, 0, 0, 5 }, { 1, 100, 100, 100, 100 }, { 0.995, 99, 100, 95, 100 } }) do
            W.unit.target.health = row[1]
            Fake.tick(3)
            assert.are.same({ row[2], row[3] }, lohi(fine), row[1])
            assert.are.same({ row[4], row[5] }, lohi(five), row[1])
        end
        fine:Release() -- the source goes back to the 5% set (6 bars) and primes again
        assert.are.equal(6, srcBars("target"))
        untilLive(five)
        assert.are.same({ 95, 100 }, lohi(five))
        assert.are.equal(0, select(6, lib:GetStats()))
    end)

    -- The client's values over the last frames, against every band a 5% watch was called with: a band must be the 5%
    -- cell of a value the client held, never a half-landed code.
    for _, case in ipairs({
        { "lag 1 and jitter 1 (every firing 1-2 frames late)", { lag = 1, jitter = 1, seed = 4242 } },
        { "stagger 2 (one change's firings over two frames)", { stagger = 2 } },
        { "lag 2", { lag = 2 } },
    }) do
        it("never reports a 5% band the client did not hold: " .. case[1], function()
            Fake.plate("nameplate5", { health = 1 })
            local h = lib:Watch("A", { kind = "health", unit = "nameplate5", step = 5 })
            Fake.login()
            untilLive(h)
            for k, v in pairs(case[2]) do
                Fake.set(k, v)
            end
            local p, r, hist, far, n = 100, 777, {}, {}, 0
            local function rnd(m) -- Park-Miller: exact in doubles
                r = r * 16807 % 2147483647
                return math.floor(r / 65536) % m
            end
            local function cell(v)
                return v == 100 and 100 or v - v % 5
            end
            h:SetSink(function(_, lo)
                if lo then
                    n = n + 1
                    local held = false
                    for k = math.max(1, #hist - 8), #hist do
                        held = held or cell(hist[k]) == lo
                    end
                    if not held then
                        far[#far + 1] = lo .. " at frame " .. #hist
                    end
                end
            end)
            for _ = 1, 3600 do
                local roll = rnd(40)
                if roll == 0 then
                    p = 20 + rnd(81) -- a heal or a new phase: a jump anywhere
                elseif roll < 12 then
                    p = math.max(0, p - 1 - rnd(3)) -- damage
                end
                W.unit.nameplate5.health = p / 100
                hist[#hist + 1] = p
                Fake.tick(1)
            end
            for k in pairs(case[2]) do
                if k ~= "seed" then
                    Fake.set(k, 0)
                end
            end
            Fake.tick(12)
            assert.is_true(n > 300, n) -- calls with a band (measured 372-401 of 3600 frames): not a run of unknowns
            assert.is_true(select(8, lib:GetStats()) > 0) -- split frames held (measured 22-404)
            assert.are.same({}, far)
            assert.are.same({ cell(p), p == 100 and 100 or cell(p) + 5 }, lohi(h))
        end)
    end

    for _, removed in ipairs({ true, false }) do
        local name = removed and "REMOVED and ADDED" or "ADDED alone"
        it(name .. " for another mob in one frame: unknown, priming, the new band with dir 0, never the old", function()
            Fake.plate("nameplate3", { health = 0.8 })
            local h = lib:Watch("A", { kind = "health", unit = "nameplate3", step = 5 }, sink)
            Fake.login()
            untilLive(h)
            assert.are.same({ 80, 85 }, lohi(h))
            if removed then
                Fake.plate("nameplate3", nil)
            end
            Fake.plate("nameplate3", { health = 0.3 })
            Fake.tick(1)
            assert.are.same({ { nil, nil, 0 } }, calls)
            assert.are.equal("priming", (h:State()))
            Fake.tick(20)
            assert.are.same({ { nil, nil, 0 }, { 30, 35, 0 } }, calls)
            assert.are.equal(0, select(6, lib:GetStats()))
        end)
    end

    -- Get in the frame of the event: never the old unit's band (the sink's unknown call still comes next frame).
    for _, case in ipairs({
        {
            "REMOVED",
            "nameplate3",
            function()
                Fake.plate("nameplate3", nil)
            end,
            "gone",
        },
        {
            "REMOVED and ADDED of another mob",
            "nameplate3",
            function()
                Fake.plate("nameplate3", nil)
                Fake.plate("nameplate3", { health = 0.3 })
            end,
            "priming",
        },
        {
            "ADDED alone of another mob",
            "nameplate3",
            function()
                Fake.plate("nameplate3", { health = 0.3 })
            end,
            "priming",
        },
        {
            "a target change",
            "target",
            function()
                W.unit.target = { health = 0.3 }
                Fake.event("PLAYER_TARGET_CHANGED")
            end,
            "priming",
        },
    }) do
        it("gives no band from Get in the frame of " .. case[1], function()
            W.unit.target = { health = 0.8 }
            Fake.plate("nameplate3", { health = 0.8 })
            local h = lib:Watch("A", { kind = "health", unit = case[2], step = 5 }, sink)
            local e = lib:Watch("B", { kind = "health", unit = case[2], edges = { 50 } })
            Fake.login()
            untilLive(h)
            untilLive(e)
            assert.are.same({ 80, 85 }, lohi(h))
            case[3]()
            assert.are.same({}, lohi(h))
            assert.are.same({}, lohi(e))
            assert.are.equal(lib.UNKNOWN, select(4, h:Get()))
            assert.are.equal(case[4], (h:State()))
            Fake.tick(20)
            local want = case[4] == "gone" and { { nil, nil, 0 } } or { { nil, nil, 0 }, { 30, 35, 0 } }
            assert.are.same(want, calls)
        end)
    end

    it("reads REMOVED alone as gone, even while UnitExists still says the token is there", function()
        Fake.plate("nameplate4", { health = 0.6 })
        local h = lib:Watch("A", { kind = "health", unit = "nameplate4", step = 5 }, sink)
        Fake.login()
        untilLive(h)
        Fake.event("NAME_PLATE_UNIT_REMOVED", "nameplate4") -- W.unit.nameplate4 kept: UnitExists true
        assert.is_true(_G.UnitExists("nameplate4"))
        Fake.tick(1)
        assert.are.equal("gone", (h:State()))
        assert.are.same({ { nil, nil, 0 } }, calls)
        lib.capChanged() -- any later sync keeps it gone
        local pushes = lib.nPush
        Fake.tick(5)
        assert.are.equal(pushes, lib.nPush)
        assert.are.equal("gone", (h:State()))
        Fake.plate("nameplate4", W.unit.nameplate4)
        Fake.tick(20)
        assert.are.same({ 60, 65 }, lohi(h))
        assert.are.same({ { nil, nil, 0 }, { 60, 65, 0 } }, calls)
    end)

    it("ignores a plate event whose unit is nil, secret or not nameplate1-40: every kind stays on", function()
        W.unit.target = { health = 0.6 }
        Fake.plate("nameplate3", { health = 0.4 })
        local t = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        local p = lib:Watch("A", { kind = "health", unit = "nameplate3", step = 5 })
        Fake.login()
        untilLive(t)
        untilLive(p)
        for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
            for _, u in ipairs({ false, Fake.secret("nameplate3"), "target", "nameplate41", "nameplate3x", 3 }) do
                if u == false then
                    Fake.event(ev)
                else
                    Fake.event(ev, u)
                end
            end
        end
        Fake.tick(3)
        assert.are.same({}, Fake.errors)
        assert.is_nil(next(lib.plateOut))
        for _, k in ipairs(lib:GetKinds()) do
            if k.kind == "health" or k.kind == "power" or k.kind == "aura" then
                assert.are.equal("ready", k.state, k.kind)
            end
        end
        assert.are.same({}, calls) -- no prime, no unknown call
        W.unit.target.health = 0.55
        Fake.tick(3)
        assert.are.same({ 55, 56 }, lohi(t))
        assert.are.same({ 40, 45 }, lohi(p))
        assert.are.equal("live", (p:State()))
    end)

    it("models UnitIsUnit by the shared unit table, and secret on the switch", function()
        local mob = { health = 0.5 }
        W.unit.target = mob
        Fake.plate("nameplate9", mob)
        Fake.plate("nameplate10", { health = 0.5 })
        assert.is_true(_G.UnitIsUnit("target", "nameplate9"))
        assert.is_false(_G.UnitIsUnit("target", "nameplate10"))
        assert.is_false(_G.UnitIsUnit("nameplate11", "nameplate12"))
        W.secretIsUnit = true
        assert.is_true(_G.issecretvalue(_G.UnitIsUnit("target", "nameplate9")))
        Fake.plate("nameplate9", nil)
        assert.is_nil(W.unit.nameplate9)
    end)

    it("allocates nothing over 1000 steady frames of four 5% plates and a 1% target", function()
        local hs = {}
        W.unit.target = { health = 0.5 }
        hs[1] = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, function() end)
        for k = 1, 4 do
            Fake.plate("nameplate" .. k, { health = 0.2 * k })
            hs[k + 1] = lib:Watch("A", { kind = "health", unit = "nameplate" .. k, step = 5 }, function() end)
        end
        Fake.login()
        for k = 1, #hs do
            untilLive(hs[k])
        end
        assert.are.equal(6, srcBars("nameplate1"))
        assert.are.equal(8 + 4 * 6, (lib:GetStats()))
        local seq = { 0.5, 0.5, 0.5, 0.43, 0.43, 0.43, 0.38, 0.38, 0.38 }
        local mobs = { W.unit.target, W.unit.nameplate1, W.unit.nameplate2, W.unit.nameplate3, W.unit.nameplate4 }
        local function frame(i)
            local v = seq[i % #seq + 1]
            for k = 1, #mobs do
                mobs[k].health = v
            end
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
        assert.is_true(grew < 0.5, grew .. " KB")
        assert.are.equal(0, select(6, lib:GetStats()))
    end)
end)
