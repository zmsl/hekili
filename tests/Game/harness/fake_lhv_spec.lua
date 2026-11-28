-- tests/Game/harness/fake_lhv_spec.lua (LibHiddenValues integration design 5.4 item 2, lane B0): the loops' fake
-- library answers the handle contract wave 1 uses (Watch, Get, State, SetPoints, SetPaused, Release, ReleaseAll,
-- IsAvailable, GetStats, Latency) with the same shapes and codes as the real library on its FakeClient, and times its
-- answers by the observer rules in its header (fires, hold, desync, prime, 1% cells, point caps). No consumer yet.
local fake_lhv = require("Game.harness.fake_lhv")
local alloc = require("Game.State.helpers.alloc")

local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"
local FRAME = 1 / 60
local PRIMED = 11 * FRAME -- a prime's first live frame (the shared rows "primes: ...")
local floor = math.floor

-- Each world: target health 63.7%, player health full, player mana 45% of 1000. `live()` runs until fresh watches are
-- live; `frame(pct)` runs one frame with the target's health at pct% (nil: unchanged); `hp(pct)` and `mana(pct)` set our
-- health and mana, seen on the next frame; `max(m)` sets the mana max (mana stays 45%), seen on the next frame; `retarget(pct)` swaps to a new
-- target at pct% (the client's PLAYER_TARGET_CHANGED); `clear()` clears the target (the same event, no unit).
local IMPLS = {
    real = function()
        local Fake = dofile(FAKE)
        local W = Fake.world
        W.unit.target = { health = 0.637 }
        W.unit.player.health = 1
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
                hp = function(pct)
                    W.unit.player.health = pct / 100
                end,
                mana = function(pct)
                    W.unit.player.power[0] = pct / 100
                end,
                max = function(m)
                    W.unit.player.max[0] = m
                    Fake.event("UNIT_MAXPOWER", "player")
                end,
                retarget = function(pct)
                    W.unit.target = { health = pct / 100 }
                    Fake.event("PLAYER_TARGET_CHANGED")
                end,
                clear = function()
                    W.unit.target = nil
                    Fake.event("PLAYER_TARGET_CHANGED")
                end,
                plate = function(pct) -- nameplate1 shows a mob at pct% (nil: its plate goes)
                    Fake.plate("nameplate1", pct and { health = pct / 100 } or nil)
                end,
                plateHp = function(pct)
                    W.unit.nameplate1.health = pct / 100
                end,
                now = rawget(_G, "GetTime"), -- the FakeClient's clock
                done = Fake.restore,
            }
    end,
    fake = function()
        local k, newMax, newHp, newMana, newPlate = 0, nil, nil, nil, nil -- k: the frame number: the clock is 1000 + k frames, never a running sum
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
                    if newHp then
                        lib:Push("health", "player", nil, newHp * 10, 1000, now())
                        newHp = nil
                    end
                    if newMana then
                        lib:Push("power", "player", 0, newMana * 10, 1000, now())
                        newMana = nil
                    end
                    if newPlate then
                        lib:Push("health", "nameplate1", nil, newPlate * 10, 1000, now())
                        newPlate = nil
                    end
                end,
                hp = function(pct)
                    newHp = pct
                end,
                mana = function(pct)
                    newMana = pct
                end,
                max = function(m)
                    newMax = m
                end,
                retarget = function(pct)
                    lib:Prime("target", now())
                    lib:Push("health", "target", nil, pct * 10, 1000, now())
                end,
                clear = function()
                    lib:Prime("target", now())
                    lib:Push("health", "target", nil, nil, nil, now())
                end,
                plate = function(pct) -- the observer's plate pushes (observer.lua plateBands)
                    if pct then
                        lib:Prime("nameplate1", now())
                    end
                    lib:Push("health", "nameplate1", nil, pct and pct * 10, pct and 1000, now())
                end,
                plateHp = function(pct)
                    newPlate = pct
                end,
                now = now,
                done = function() end,
            }
    end,
}

-- The target's health one frame at a time, pinned on the real library (LibHiddenValues README, "Confirmation"): each
-- case's row is the step watch's lo after every frame ("-": unknown; "lo@n": its t n frames old, for a change of the
-- sequence), the frames of `seq` then `idle` frames unchanged.
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
        "63 63 63 63 63 63 58@2 58@3",
    },
    {
        "one cell a frame for 6 frames: never confirmed, unknown, primes again",
        down(62.5, 6),
        12,
        "63 63 63 63 63 63 - - - - - - - - - - 57@2 57@3",
    },
    {
        "one cell a frame for 7 frames",
        down(62.5, 7),
        12,
        "63 63 63 63 63 63 - - - - - - - - - - 56@2 56@3 56@4",
    },
    {
        "a fall of 30 frames: unknown until it stops",
        down(62.5, 30),
        4,
        "63 63 63 63 63 63 - - - - - - - - - - - - - - - - - - - - - - - - - 33@2 33@3 33@4",
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
        "63 63 63 63 63 63 - - - - - - - - - - 61@2 61@3 61@4 61@5 61@6 61@7",
    },
    {
        "moving inside the held cell: nothing fires",
        { 63.6, 63.5, 63.4, 63.3, 63.2, 63.1, 63.05, 63.9 },
        2,
        "63 63 63 63 63 63 63 63 63 63",
    },
}

-- A prime, pinned on the real library (ledger L1664 item 1, the B0 re-review's retarget probe): a watch made after
-- login, a resume and a retarget are unknown 10 frames, then the band stamped at the prime's end (2 frames back); a
-- change during the prime is reported with it, one on the first live frame is held as any change. Each case: how it
-- primes, the new target's health (a retarget), a move { frame, pct } of the target, the frames read, the row (lo@age
-- after every frame).
local PRIMES = {
    { "a watch made after login", "watch", nil, nil, 13, "- - - - - - - - - - 63@2 63@3 63@4" },
    { "a resume", "resume", nil, nil, 13, "- - - - - - - - - - 63@2 63@3 63@4" },
    { "a retarget to a still target", "retarget", 19.5, nil, 16, "- - - - - - - - - - 19@2 19@3 19@4 19@5 19@6 19@7" },
    {
        "a retarget, the new target moving during the prime",
        "retarget",
        50.5,
        { 4, 48.5 },
        13,
        "- - - - - - - - - - 48@2 48@3 48@4",
    },
    {
        "a retarget, the new target moving on the first live frame",
        "retarget",
        50.5,
        { 11, 48.5 },
        14,
        "- - - - - - - - - - 50@2 50@3 48@2 48@3",
    },
}

local function get(h)
    return { h:Get() }
end

-- lo, hi and q (Get's t left out)
local function unknown(h)
    local lo, hi, _, q = h:Get()
    return { lo, hi, q }
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

        -- (ledger L1669) full is its own closed cell [100, 100]; 99.0 up to just under full is [99, 100) (99.95-99.99
        -- sits in the library's 0.05% guard below the edge and reads either way, by the client's snap: not a row)
        it("full health is the closed cell [100, 100], 99.6 and 99.0 the cell [99, 100); player and target", function()
            local tgt = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
            local me = assert(lib:Watch("A", { kind = "health", unit = "player", step = 1 }))
            local pts = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = {} }))
            w.live()
            local rows = {}
            for _, pct in ipairs({ 100, 99.6, 100 - 1, 100 }) do -- 100 - 1: a bare 99 is a spell ID to boundary_spec
                w.hp(pct)
                w.frame(pct)
                for _ = 1, 3 do
                    w.frame()
                end
                rows[#rows + 1] = table.concat({ pct, unpack(lohi(tgt)) }, " ")
                rows[#rows + 1] = table.concat({ pct, unpack(lohi(me)) }, " ")
            end
            w.retarget(100) -- a full target after a target change (lane B2's pull)
            for _ = 1, 12 do
                w.frame()
            end
            rows[#rows + 1] = table.concat({ "retarget", unpack(lohi(tgt)) }, " ")
            assert.are.same({
                "100 100 100",
                "100 100 100",
                "99.6 99 100",
                "99.6 99 100",
                "99 99 100",
                "99 99 100",
                "100 100 100",
                "100 100 100",
                "retarget 100 100",
            }, rows)
            w.mana(100) -- a points handle's full cell: [max, max]
            for _ = 1, 4 do
                w.frame()
            end
            assert.are.same({ 1000, 1000 }, lohi(pts))
        end)

        -- (minor 9, L1712) health exactly empty is the closed cell [0, 0], a little left [0, 1) ("above 0"); power at 0
        -- keeps its bottom cell
        it(
            "health exactly empty reads [0, 0], a little left [0, 1); player and target; power at 0 keeps [0, 10]",
            function()
                local tgt = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
                local me = assert(lib:Watch("A", { kind = "health", unit = "player", step = 1 }))
                local pts =
                    assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = {} }))
                w.live()
                local rows = {}
                for _, pct in ipairs({ 0, 0.05, 0, 37 }) do
                    w.hp(pct)
                    w.frame(pct)
                    for _ = 1, 3 do
                        w.frame()
                    end
                    rows[#rows + 1] = table.concat({ pct, unpack(lohi(tgt)) }, " ")
                    rows[#rows + 1] = table.concat({ pct, unpack(lohi(me)) }, " ")
                end
                assert.are.same({
                    "0 0 0",
                    "0 0 0",
                    "0.05 0 1",
                    "0.05 0 1",
                    "0 0 0",
                    "0 0 0",
                    "37 37 38",
                    "37 37 38",
                }, rows)
                w.mana(0)
                for _ = 1, 4 do
                    w.frame()
                end
                assert.are.same({ 0, 10 }, lohi(pts))
            end
        )

        -- (minor 10, L1804) a retarget or a cleared target drops the band in the event's own frame: Get never gives the
        -- last unit's band (minor 9 kept it for the rest of that frame); a paused watch on the source drops it too
        it(
            "a retarget and a cleared target read nil at once, a paused watch too; the new unit live after its prime",
            function()
                local hp = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
                local held = assert(lib:Watch("B", { kind = "health", unit = "target", step = 1 }))
                w.live()
                held:SetPaused(true)
                assert.are.same({ 63, 64 }, lohi(hp))
                assert.are.same({ 63, 64 }, lohi(held))
                w.retarget(19.5)
                assert.are.same({ nil, nil, lib.UNKNOWN }, unknown(hp)) -- t: the real library keeps the last stamp
                assert.are.same({ nil, nil, lib.UNKNOWN }, unknown(held))
                assert.are.equal("priming", hp:State())
                for _ = 1, 12 do
                    w.frame()
                end
                assert.are.same({ "live", 19, 20 }, { hp:State(), unpack(lohi(hp)) })
                w.clear()
                assert.are.same({ nil, nil, lib.UNKNOWN }, unknown(hp))
                assert.are.equal("gone", hp:State())
            end
        )

        -- (minor 10) a plate's health at the 5% step: the 5% cell, 95-99 [95, 100], full [100, 100], empty [0, 5]; its
        -- REMOVED reads gone (the ttd arm's plates, observer.lua plateBands)
        it(
            "a plate at step 5: the 5% cell, 95-99 [95, 100], full [100, 100], empty [0, 5]; removed reads gone",
            function()
                local h = assert(lib:Watch("A", { kind = "health", unit = "nameplate1", step = 5 }))
                w.plate(63.7)
                w.live()
                local rows = { table.concat(lohi(h), " ") }
                for _, pct in ipairs({ 61, 97, 100, 0, 3 }) do
                    w.plateHp(pct)
                    for _ = 1, 4 do
                        w.frame()
                    end
                    rows[#rows + 1] = table.concat({ pct, unpack(lohi(h)) }, " ")
                end
                assert.are.same({ "60 65", "61 60 65", "97 95 100", "100 100 100", "0 0 5", "3 0 5" }, rows)
                w.plate(nil)
                assert.are.same({ "gone", nil }, { h:State(), (h:Get()) })
            end
        )

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
            assert.are.same({ "LibHiddenValues-1.0", 10 }, { lib:GetVersion() })
            local verdict, lines, running = lib:GetSelfTest()
            assert.are.same({ true, "table", false }, { verdict, type(lines), running })
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
                local row, t0 = {}, w.now()
                local function read()
                    local lo, _, t = hp:Get()
                    local age = lo and t >= t0 and floor((w.now() - t) / FRAME + 0.5)
                    row[#row + 1] = lo and (age and lo .. "@" .. age or tostring(lo)) or "-"
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

        for _, case in ipairs(PRIMES) do
            it("primes: " .. case[1], function()
                local how, move = case[2], case[4]
                local hp
                if how ~= "watch" then
                    hp = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
                end
                w.live()
                if how == "watch" then
                    hp = assert(lib:Watch("A", { kind = "health", unit = "target", step = 1 }))
                elseif how == "resume" then
                    hp:SetPaused(true)
                    for _ = 1, 5 do
                        w.frame(nil)
                    end
                    hp:SetPaused(false)
                else
                    w.retarget(case[3])
                end
                local row = {}
                for i = 1, case[5] do
                    w.frame(move and move[1] == i and move[2] or nil)
                    local lo, _, t = hp:Get()
                    local live = hp:State() == "live" and lo ~= nil
                    row[i] = live and lo .. "@" .. floor((w.now() - t) / FRAME + 0.5) or "-"
                end
                assert.are.equal(case[6], table.concat(row, " "))
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

        -- (ledger L1664 items 2-3, lane B4) points beside a step on one mana source, pinned on the real library: a
        -- point inside a cell fires one bar (a frame), a cell change is confirmed (2 frames), and each handle's t is
        -- its own band's change. `one`: Hekili's shape, one handle with both; `two`: two watches.
        local function shown(h, t0)
            local lo, hi, t = h:Get()
            if h:State() ~= "live" or not lo then
                return "-"
            end
            return t >= t0 and ("%d-%d@%d"):format(lo, hi, floor((w.now() - t) / FRAME + 0.5)) or lo .. "-" .. hi
        end
        local SLOW = { 45.35, 45.55, 45.75, 45.95, 46.15, 46.35, 46.55 }
        for _, case in ipairs({
            { "one", "a point inside the cell: a frame", { 45.55 }, 3, "450-453 455-460@1 455-460@2 455-460@3" },
            {
                "one",
                "back over a point",
                { 45.55, false, false, 45.2 },
                2,
                "450-453 455-460@1 455-460@2 455-460@3 450-453@1 450-453@2",
            },
            {
                "one",
                "two points a frame apart",
                { 45.32, 45.75 },
                2,
                "450-453 453-455@1 455-460@1 455-460@2",
            },
            { "one", "a cell: two frames", { 46.2 }, 2, "450-453 450-453 460-465@2" },
            { "one", "a point and a cell at once", { 46.6 }, 2, "450-453 450-453 465-470@2" },
            { "one", "a point while a cell waits", { 46.2, 46.6 }, 2, "450-453 450-453 465-470@1 465-470@2" },
            { "one", "a point, then a cell", { 45.55, 46.2 }, 3, "450-453 455-460@1 455-460@2 460-465@2 460-465@3" },
            {
                "one",
                "point crossings while moving",
                SLOW,
                2,
                "450-453 453-455@1 455-460@1 455-460@2 455-460@3 455-460@4 460-465@2 465-470@1 465-470@2",
            },
            {
                "two",
                "a point, then a cell",
                { 45.55, 46.2 },
                3,
                "0-453|450-460 455-465@1|450-460 455-465@2|450-460 455-465@3|460-470@2 455-465@4|460-470@3",
            },
            {
                "two",
                "point crossings while moving",
                SLOW,
                2,
                "0-453|450-460 453-455@1|450-460 455-465@1|450-460 455-465@2|450-460 455-465@3|450-460 455-465@4|450-460 "
                    .. "455-465@5|460-470@2 465-1000@1|460-470@3 465-1000@2|460-470@4",
            },
        }) do
            it("points and a step (" .. case[1] .. "): " .. case[2], function()
                -- 450 + n: a bare literal would read as a spell ID (boundary_spec)
                local spec = { kind = "power", unit = "player", power = 0, points = { 450 + 3, 455, 450 + 15 } }
                spec.step = case[1] == "one" and 1 or nil
                local a, b = assert(lib:Watch("A", spec)), nil
                if case[1] == "two" then
                    b = assert(lib:Watch("B", { kind = "power", unit = "player", power = 0, step = 1, points = {} }))
                end
                w.live()
                w.frame()
                w.frame()
                local t0, row = w.now(), {}
                for i = 1, #case[3] + case[4] do
                    if case[3][i] then
                        w.mana(case[3][i])
                    end
                    w.frame()
                    row[i] = shown(a, t0) .. (b and "|" .. shown(b, t0) or "")
                end
                assert.are.equal(case[5], table.concat(row, " "))
            end)
        end

        it(
            "SetPoints: a new point bar primes (9 frames, t its end); the same, a grid point or none does not",
            function()
                local h = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = {} }))
                w.live()
                w.frame()
                local t0 = w.now()
                local function run(list, n)
                    assert.is_true(h:SetPoints(list))
                    local row = {}
                    for i = 1, n do
                        w.frame()
                        row[i] = shown(h, t0)
                    end
                    return table.concat(row, " ")
                end
                assert.are.same({
                    ("- "):rep(9) .. "450-455@1 450-455@2",
                    "450-455@3",
                    "450-455@4",
                    "450-460@0", -- a removed point widens the band: a change, seen that frame
                }, { run({ 455 }, 11), run({ 455 }, 1), run({ 455, 460 }, 1), run({}, 1) })
            end
        )

        it("a max change on points beside a step: t is the new bars' prime end", function()
            local h = assert(lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = { 455 } }))
            w.live()
            w.frame()
            local t0, row = w.now(), {}
            w.max(1200)
            for i = 1, 11 do
                w.frame()
                row[i] = shown(h, t0)
            end
            assert.are.equal(("- "):rep(9) .. "540-552@1 540-552@2", table.concat(row, " "))
        end)

        for _, how in ipairs({ "watch", "resume" }) do
            it("a step with points after a " .. how .. ": the band, t the prime's end (L1664 item 2)", function()
                local spec = { kind = "power", unit = "player", power = 0, step = 1, points = { 455 } }
                local h
                if how == "resume" then
                    h = assert(lib:Watch("A", spec))
                end
                w.live()
                local t0 = w.now()
                if how == "watch" then
                    h = assert(lib:Watch("A", spec))
                else
                    h:SetPaused(true)
                    w.frame()
                    h:SetPaused(false)
                end
                local row = {}
                for i = 1, 12 do
                    w.frame()
                    row[i] = shown(h, t0)
                end
                assert.are.equal(("- "):rep(10) .. "450-455@2 450-455@3", table.concat(row, " "))
            end)
        end
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
        t = t + PRIMED
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
        local t0 = t + PRIMED
        for i = 1, 6 do -- the shared block's 6-frame case, read only at its frames 16 and 17
            lib:Push("health", "target", nil, 895 - 10 * i, 1000, t0 + i * FRAME)
        end
        t = t0 + 16 * FRAME
        assert.are.same({ "priming", nil }, { h:State(), (h:Get()) })
        t = t0 + 17 * FRAME
        assert.are.same({ 83, 84, t0 + 15 * FRAME, lib.BAND }, { h:Get() }) -- t: the prime's end, 2 frames back
    end)

    it("primes 10 frames after a watch, a resume and a unit change, then answers the current value", function()
        local t0 = t
        lib:Push("health", "target", nil, 600, 1000, t0)
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
        t = t0 + 10 * FRAME
        assert.are.equal("priming", (h:State()))
        t = t0 + PRIMED
        assert.are.same({ 60, 61, t0 + 9 * FRAME, lib.BAND }, { h:Get() }) -- t: the prime's end, 2 frames back
        local t1 = t
        lib:Prime("target", t1)
        lib:Push("health", "target", nil, 300, 1000, t1)
        t = t1 + 10 * FRAME
        assert.are.same({ "priming", nil }, { h:State(), (h:Get()) })
        t = t1 + PRIMED
        assert.are.same({ 30, 31, t1 + 9 * FRAME, lib.BAND }, { h:Get() })
        h:SetPaused(true)
        h:SetPaused(false)
        assert.are.equal("priming", (h:State()))
        t = t + PRIMED
        assert.are.equal("live", (h:State()))
    end)

    it("1% cells are exact for whole values; full is its own cell [100, 100], empty [0, 0]; no unit is gone", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1, edges = { 35 } })
        t = t + PRIMED
        for _, c in ipairs({
            { 29, 100, 29, 30 },
            { 1000, 1000, 100, 100 },
            { 995, 1000, 100 - 1, 100 },
            { 0, 1000, 0, 0 },
            { 1, 1000, 0, 1 },
            { 1, 2000000, 0, 0 }, -- under max / 1,000,000: empty (the library's stated limit)
            { 2, 1000000, 0, 1 },
            { 3550, 10000, 35, 36 },
        }) do
            lib:Push("health", "target", nil, c[1], c[2], t)
            t = t + 2 * FRAME
            assert.are.same({ c[3], c[4] }, lohi(h), c[1])
        end
        local e = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50 } })
        t = t + PRIMED
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
        t = t + PRIMED
        lib:SetAvailable("unavailable", "selftest")
        assert.are.same({ "unavailable", "selftest" }, { h:State() })
        assert.are.same({ false, "unavailable", "selftest" }, { lib:IsAvailable("health", "target") })
        assert.is_false((lib:GetSelfTest()))
        assert.is_nil((h:Get()))
        lib:SetAvailable("ready")
        assert.are.same({ 50, 51 }, lohi(h))
    end)

    it("Get and State allocate nothing", function()
        local h = lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = { 40 } })
        lib:Push("power", "player", 0, 45, 100, t)
        t = t + PRIMED
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

-- (lane aura-stacks) the opt-in aura kind (o.auras, the aura-bands arm): the real library's stacks bands from the
-- observer's pushes, AURA_LAG (5) frames late; off without o.auras (every other arm: unproven, as before)
describe("fake_lhv's aura kind", function()
    local t
    local function lib(placed)
        return fake_lhv.new({
            now = function()
                return t
            end,
            auras = placed,
        })
    end
    local SPEC = { kind = "aura", unit = "player", spell = 77, what = "stacks", edges = { 1, 3, 4 }, max = 5 }
    local function band(h)
        local lo, hi = h:Get()
        return { lo, hi }
    end

    it("is unproven without o.auras", function()
        t = 0
        local h = lib(nil):Watch("O", SPEC)
        assert.are.same({ "unavailable", "unproven" }, { h:State() })
    end)

    it("bands the pushed stacks 5 frames late, absent before any push, unplaced unavailable", function()
        t = 0
        local on = true
        local L = lib(function(spell)
            return on and spell == 77
        end)
        local h = L:Watch("O", SPEC)
        assert.are.equal("priming", (h:State()))
        t = 5 * FRAME
        assert.are.same({ 0, 1 }, band(h))
        L:Push("aura", "player", 77, 1, nil, t)
        assert.are.same({ 0, 1 }, band(h)) -- not shown yet
        t = t + 5 * FRAME
        assert.are.same({ 0, 3 }, band(h)) -- up with no count: 0 to the lowest bar
        L:Push("aura", "player", 77, 3, nil, t)
        t = t + 5 * FRAME
        local lo, hi, bt = h:Get()
        assert.are.same({ 3, 4 }, { lo, hi })
        assert.is_true(math.abs(bt - t) < 1e-9)
        L:Push("aura", "player", 77, 5, nil, t)
        t = t + 5 * FRAME
        assert.are.same({ 4, 5 }, band(h))
        on = false
        assert.are.same({ "unavailable", "cdm-not-tracked" }, { h:State() })
        on = true
        L:AuraReset()
        assert.are.same({ 0, 1 }, band(h))
    end)
end)
