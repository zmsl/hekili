-- tests/Game/harness/fake_lhv_spec.lua (LibHiddenValues integration design 5.4 item 2, lane B0): the loops' fake
-- library answers the handle contract wave 1 uses (Watch, Get, State, SetPoints, SetPaused, Release, ReleaseAll,
-- IsAvailable, GetStats, Latency) with the same shapes and codes as the real library on its FakeClient, and times its
-- answers by the observer rules in its header (hold, latency, prime, 1% cells, point caps). No consumer yet.
local fake_lhv = require("Game.harness.fake_lhv")
local alloc = require("Game.State.helpers.alloc")

local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"
local FRAME = 1 / 60

-- Each world: target health 63.7%, player mana 45% of 1000. `live()` runs until fresh watches are live; `frame(pct)`
-- runs one frame with the target's health at pct% (nil: unchanged); `max(m)` sets the mana max (mana stays 45%), seen
-- on the next frame.
local IMPLS = {
    real = function()
        local Fake = dofile(FAKE)
        local W = Fake.world
        W.unit.target = { health = 0.637 }
        W.unit.player.power[0], W.unit.player.max[0] = 0.45, 1000
        return LibStub("LibHiddenValues-1.0"),
            {
                live = function()
                    Fake.login()
                    Fake.tick(12)
                end,
                frame = function(pct)
                    if pct then
                        W.unit.target.health = pct / 100
                    end
                    Fake.tick(1)
                end,
                max = function(m)
                    W.unit.player.max[0] = m
                    Fake.event("UNIT_MAXPOWER", "player")
                end,
                done = Fake.restore,
            }
    end,
    fake = function()
        local k, newMax = 0, nil -- the frame number: the clock is 1000 + k frames, never a running sum
        local function now()
            return 1000 + k * FRAME
        end
        local lib = fake_lhv.new({ now = now })
        lib:Push("health", "target", nil, 637, 1000, now())
        lib:Push("health", "player", nil, 1000, 1000, now())
        lib:Push("power", "player", 0, 450, 1000, now())
        return lib,
            {
                live = function()
                    k = k + 12
                end,
                frame = function(pct)
                    k = k + 1
                    if pct then
                        lib:Push("health", "target", nil, pct * 10, 1000, now())
                    end
                    if newMax then
                        lib:Push("power", "player", 0, 0.45 * newMax, newMax, now())
                        newMax = nil
                    end
                end,
                max = function(m)
                    newMax = m
                end,
                done = function() end,
            }
    end,
}

-- The target's health one frame at a time, pinned on the real library (LibHiddenValues README, "Confirmation"): each
-- case's row is the step watch's lo after every frame ("-": unknown), the frames of `seq` then `idle` frames unchanged.
local function down(from, n)
    local seq = {}
    for i = 1, n do
        seq[i] = from - (i - 1)
    end
    return seq
end
local function alternate(a, b, n)
    local seq = {}
    for i = 1, n do
        seq[i] = i % 2 == 1 and a or b
    end
    return seq
end
local SEQUENCES = {
    {
        "one cell a frame for 5 frames: confirmed 2 frames after the last",
        down(62.5, 5),
        3,
        "63 63 63 63 63 63 58 58",
    },
    {
        "one cell a frame for 6 frames: never confirmed, unknown, primes again",
        down(62.5, 6),
        12,
        "63 63 63 63 63 63 - - - - - - - - - - 57 57",
    },
    {
        "one cell a frame for 7 frames",
        down(62.5, 7),
        12,
        "63 63 63 63 63 63 - - - - - - - - - - 56 56 56",
    },
    {
        "a fall of 30 frames: unknown until it stops",
        down(62.5, 30),
        4,
        "63 63 63 63 63 63 - - - - - - - - - - - - - - - - - - - - - - - - - 33 33 33",
    },
    {
        "alternating with the held cell: the held cell throughout",
        alternate(62.5, 63.5, 10),
        3,
        "63 63 63 63 63 63 63 63 63 63 63 63 63",
    },
    {
        "alternating between two other cells: never confirmed",
        alternate(62.5, 61.5, 10),
        12,
        "63 63 63 63 63 63 - - - - - - - - - - 61 61 61 61 61 61",
    },
    {
        "moving inside the held cell: nothing fires",
        { 63.6, 63.5, 63.4, 63.3, 63.2, 63.1, 63.05, 63.9 },
        2,
        "63 63 63 63 63 63 63 63 63 63",
    },
}

local function get(h)
    return { h:Get() }
end

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

for _, name in ipairs({ "real", "fake" }) do
    describe("the LibHiddenValues contract (" .. name .. ")", function()
        local lib, w

        before_each(function()
            lib, w = IMPLS[name]()
        end)
        after_each(function()
            w.done()
        end)

        it("refuses a bad spec with the library's codes", function()
            local bad = {
                { 1, { kind = "health", unit = "target", step = 1 } },
                { "A", "x" },
                { "A", { kind = "nope" } },
                { "A", { kind = "health" } },
                { "A", { kind = "health", unit = "target" } },
                { "A", { kind = "health", unit = "target", step = 0 } },
                { "A", { kind = "health", unit = "target", edges = { 0 } } },
                { "A", { kind = "health", unit = "target", edges = { "x" } } },
                { "A", { kind = "power", unit = "player", step = 1 } },
                { "A", { kind = "power", unit = "player", power = "mana", step = 1 } },
                { "A", { kind = "power", unit = "player", power = 0, points = { 1.5 } } },
                { "A", { kind = "power", unit = "player", power = 0, points = { 1, 2, 3, 4, 5, 6, 7, 8, 9 } } },
            }
            local codes = {}
            for i, b in ipairs(bad) do
                local h, code = lib:Watch(b[1], b[2])
                assert.is_nil(h, i)
                codes[i] = code
            end
            assert.are.same({
                "owner-invalid",
                "spec-invalid",
                "kind-invalid",
                "unit-invalid",
                "edges-required",
                "step-invalid",
                "edges-out-of-range",
                "edges-invalid",
                "power-required",
                "power-invalid",
                "points-invalid",
                "edge-limit",
            }, codes)
            assert.are.same({ nil, "sink-invalid" }, {
                lib:Watch("A", { kind = "health", unit = "target", step = 1 }, 5),
            })
        end)

        it("primes, then answers the 1% cell and the point bands; unknown means nil, nil, nil, UNKNOWN", function()
            local hp = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
            local pts = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, points = { 400, 600 } }))
            local cell = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = {} }))
            assert.is_truthy(({ pending = true, priming = true })[hp:State()])
            assert.are.same({ nil, nil, nil, lib.UNKNOWN }, get(hp))
            w.live()
            assert.are.same({ "live", "live", "live" }, { hp:State(), pts:State(), cell:State() })
            local lo, hi, t, q = hp:Get()
            assert.are.same({ 63, 64, lib.BAND }, { lo, hi, q })
            assert.is_number(t)
            assert.are.same({ 400, 600 }, lohi(pts))
            assert.are.same({ 450, 460 }, lohi(cell))
            assert.are.near(7 * FRAME, hp:Latency(), 1e-9)
        end)

        it("SetPoints: true, or nil and a code with the old set kept", function()
            local hp = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
            local pts = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, points = { 400, 600 } }))
            w.live()
            assert.are.same({ nil, "points-invalid" }, { hp:SetPoints({ 10 }) })
            assert.are.same({ nil, "edge-limit" }, { pts:SetPoints({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }) })
            assert.are.same({ 400, 600 }, lohi(pts))
            assert.is_true(pts:SetPoints({ 300, 500 }))
            w.live()
            assert.are.same({ 300, 500 }, lohi(pts))
        end)

        it("IsAvailable, GetStats, an unproven unit, pause and release", function()
            local hp = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
            local other = assert(lib:Watch("B", { kind = "health", unit = "player", step = 1 }))
            local focus = assert(lib:Watch("A", { kind = "health", unit = "focus", step = 1 }))
            w.live()
            assert.are.same({ true, "ready" }, { lib:IsAvailable("health", "target") })
            assert.are.same({ false, "unavailable", "unproven" }, { lib:IsAvailable("health", "focus") })
            assert.are.same({ "unavailable", "unproven" }, { focus:State() })
            local stats = { lib:GetStats() }
            assert.are.equal(8, #stats)
            for i = 1, 8 do
                assert.is_number(stats[i], i)
            end
            hp:SetPaused(true)
            assert.are.equal("paused", (hp:State()))
            assert.are.same({ 63, 64 }, lohi(hp)) -- a paused handle keeps its last band: only State says paused
            hp:SetPaused(false)
            w.live()
            assert.are.equal("live", (hp:State()))
            lib:ReleaseAll("A")
            assert.are.same({ "released", "released", "live" }, { hp:State(), focus:State(), other:State() })
            local lo, hi, _, q = hp:Get() -- t may stay (the real library keeps it)
            assert.are.same({ nil, nil, lib.UNKNOWN }, { lo, hi, q })
            other:Release()
            assert.are.equal("released", (other:State()))
        end)

        for _, case in ipairs(SEQUENCES) do
            it(case[1], function()
                local hp = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
                w.live()
                local row = {}
                local function read()
                    row[#row + 1] = tostring((hp:Get()) or "-")
                end
                for _, pct in ipairs(case[2]) do
                    w.frame(pct)
                    read()
                end
                for _ = 1, case[3] do
                    w.frame(nil)
                    read()
                end
                assert.are.equal(case[4], table.concat(row, " "))
            end)
        end

        it("a points handle primes again when the max moves; a cell handle on the same source does not", function()
            local pts = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, points = { 400, 600 } }))
            local cell = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = {} }))
            w.live()
            w.max(1200)
            local row = {}
            for _ = 1, 11 do
                w.frame(nil)
                local a, b = pts:Get()
                local c, d = cell:Get()
                row[#row + 1] = (a and a .. "-" .. b or "-") .. "|" .. c .. "-" .. d
            end
            assert.are.equal(string.rep("-|540-552 ", 9) .. "400-600|540-552 400-600|540-552", table.concat(row, " "))
        end)
    end)
end

describe("fake_lhv's observer rules", function()
    local lib, t

    before_each(function()
        t = 1000
        lib = fake_lhv.new({
            now = function()
                return t
            end,
        })
    end)

    it("a change is reported 2 frames after its last firing, with t that firing's", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        lib:Push("health", "target", nil, 500, 1000, t)
        t = t + 10 * FRAME
        assert.are.same({ 50, 51 }, lohi(h))
        local t0 = t
        lib:Push("health", "target", nil, 480, 1000, t0)
        t = t0 + FRAME
        assert.are.same({ 50, 51 }, lohi(h))
        t = t0 + 2 * FRAME
        assert.are.same({ 48, 49, t0, lib.BAND }, { h:Get() })
    end)

    it("a read after a long gap applies the desync, the prime's decode and the report in order", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        lib:Push("health", "target", nil, 900, 1000, t)
        local t0 = t + 10 * FRAME
        for i = 1, 6 do -- the shared block's 6-frame case, read only at its frames 16 and 17
            lib:Push("health", "target", nil, 895 - 10 * i, 1000, t0 + i * FRAME)
        end
        t = t0 + 16 * FRAME
        assert.are.same({ "priming", nil }, { h:State(), (h:Get()) })
        t = t0 + 17 * FRAME
        assert.are.same({ 83, 84, t0 + 6 * FRAME, lib.BAND }, { h:Get() })
    end)

    it("primes 10 frames after a watch, a resume and a unit change, then answers the current value", function()
        local t0 = t
        lib:Push("health", "target", nil, 600, 1000, t0)
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        t = t0 + 9 * FRAME
        assert.are.equal("priming", (h:State()))
        t = t0 + 10 * FRAME
        assert.are.same({ 60, 61 }, lohi(h))
        local t1 = t
        lib:Prime("target", t1)
        lib:Push("health", "target", nil, 300, 1000, t1)
        t = t1 + 9 * FRAME
        assert.are.same({ "priming", nil }, { h:State(), (h:Get()) })
        t = t1 + 10 * FRAME
        assert.are.same({ 30, 31 }, lohi(h))
        h:SetPaused(true)
        h:SetPaused(false)
        assert.are.equal("priming", (h:State()))
        t = t + 10 * FRAME
        assert.are.equal("live", (h:State()))
    end)

    it("1% cells are exact for whole values; the top cell holds 100; no unit is gone", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1, edges = { 35 } })
        t = t + 10 * FRAME
        for _, c in ipairs({
            { 29, 100, 29, 30 },
            { 1000, 1000, 100 - 1, 100 },
            { 0, 1000, 0, 1 },
            { 3550, 10000, 35, 36 },
        }) do
            lib:Push("health", "target", nil, c[1], c[2], t)
            t = t + 2 * FRAME
            assert.are.same({ c[3], c[4] }, lohi(h), c[1])
        end
        local e = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50 } })
        t = t + 10 * FRAME
        assert.are.same({ 20, 50 }, lohi(e))
        lib:Push("health", "target", nil, nil, nil, t)
        assert.are.same({ "gone", nil }, { h:State(), (h:Get()) })
    end)

    it("the point caps: 8 distinct per source (identical points share), a total over the sources", function()
        local function watch(owner, power, list)
            return lib:Watch(owner, { kind = "power", unit = "player", power = power, points = list })
        end
        local a = assert(watch("A", 0, { 1, 2, 3, 4 }))
        assert.is_table(watch("B", 0, { 1, 2, 5, 6, 7, 8 }))
        assert.are.same({ nil, "edge-limit" }, { watch("C", 0, { 9 }) })
        assert.is_true(a:SetPoints({ 1, 2 }))
        assert.is_table(watch("C", 0, { 9 }))
        local small = fake_lhv.new({
            now = function()
                return t
            end,
            pointTotal = 10,
        })
        assert.is_table(
            small:Watch("A", { kind = "power", unit = "player", power = 0, points = { 1, 2, 3, 4, 5, 6, 7, 8 } })
        )
        assert.is_table(small:Watch("A", { kind = "power", unit = "player", power = 3, points = { 1, 2 } }))
        assert.are.same({ nil, "edge-limit" }, {
            small:Watch("A", { kind = "power", unit = "player", power = 1, points = { 1 } }),
        })
    end)

    it("the capability: SetAvailable makes every handle unknown with its reason", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        lib:Push("health", "target", nil, 500, 1000, t)
        t = t + 10 * FRAME
        lib:SetAvailable("unavailable", "selftest")
        assert.are.same({ "unavailable", "selftest" }, { h:State() })
        assert.are.same({ false, "unavailable", "selftest" }, { lib:IsAvailable("health", "target") })
        assert.is_nil((h:Get()))
        lib:SetAvailable("ready")
        assert.are.same({ 50, 51 }, lohi(h))
    end)

    it("Get and State allocate nothing", function()
        local h = lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = { 40 } })
        lib:Push("power", "player", 0, 45, 100, t)
        t = t + 10 * FRAME
        local live = 0
        local bytes = alloc.bytes(function(i)
            t = t + FRAME
            if i % 3 == 0 then -- a change every 3 frames: each confirmed, so Get answers bands, not unknown
                lib:Push("power", "player", 0, 40 + i % 7, 100, t)
            end
            if h:State() == "live" and h:Get() then
                live = live + 1
            end
        end, 1000)
        assert.are.equal(0, bytes)
        assert.are.equal(1201, live) -- every call: the warm-up's 200, the absorbing 1 and the measured 1000
    end)
end)
