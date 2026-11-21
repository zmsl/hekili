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

    -- Fix round 3: every change waits for the next frame's decode to agree (the confirm hold), so a jump is called two
    -- frames after its push (it was one).
    it("gives the 1% cell from 8 bars, any jump in one call two frames later", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        Fake.login()
        untilLive(h)
        assert.are.same({ 37, 38 }, lohi(h))
        assert.are.same({ 1, 0, 100 }, { h:Domain() })
        assert.are.equal(8, srcBars("health"))
        for _, v in ipairs({ 0.38, 0.375, 0.91, 0.05, 0, 1, 0.999, 0.5 }) do
            W.unit.target.health = v
            Fake.tick(3)
            local n = math.floor(v * 100 + 1e-9)
            assert.are.same({ n, math.min(n + 1, 100) }, lohi(h), v)
        end
        W.unit.target.health = 0.62
        Fake.tick(3)
        calls = {}
        W.unit.target.health = 0.13
        Fake.tick(1)
        assert.are.same({}, calls) -- decoded at the start of the next frame
        Fake.tick(1)
        assert.are.same({}, calls) -- held: the next frame's decode must agree
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
        Fake.tick(3) -- the push, the held decode, the confirming decode (fix round 3)
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
        Fake.tick(3) -- each change: the push, a held decode, the confirming one (fix round 3)
        assert.are.same({ 33.5, 34 }, lohi(h))
        W.unit.target.health = 0.334
        Fake.tick(3)
        assert.are.same({ 33, 33.5 }, lohi(h))
        W.unit.target.health = 0.6
        Fake.tick(3)
        assert.are.same({ 50, 100 }, lohi(e))
        W.unit.target.health = 0.19
        Fake.tick(3)
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
        local worst = 0
        for v = 38, 60 do
            W.unit.target.health = v / 100
            local f = 0
            repeat
                f = f + 1
                Fake.tick(1)
            until h:Get() == v or f == 10
            worst = math.max(worst, f)
        end
        Fake.tick(3)
        assert.is_true(worst * lib.frameSec <= h:Latency() + 1e-9, "frames " .. worst) -- the held frame counted
        local e = lib:Watch("B", { kind = "health", unit = "target", edges = { 50 } }) -- decoded after the cell too
        assert.are.equal(h:Latency(), e:Latency())
        for i = 1, #calls do
            local c = calls[i]
            assert.are.equal(c[1] + 1, c[2], i)
            assert.is_true(c[1] >= 37 and c[1] <= 60, i)
        end
        assert.are.same({ 60, 61 }, lohi(h))
        assert.is_true(select(8, lib:GetStats()) > 0) -- splits counted
        assert.are.equal(0, select(6, lib:GetStats()))
    end)

    it("primes a bar added to a live position source without a desync (a new edge, a point, a new max)", function()
        W.unit.target.health = 0.8
        local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 }, sink)
        Fake.login()
        untilLive(h)
        local e = lib:Watch("B", { kind = "health", unit = "target", edges = { 35.5 } }) -- off the 1% grid: a bar
        Fake.tick(20)
        assert.are.equal("live", (e:State()))
        assert.are.same({ 35.5, 100 }, lohi(e))
        assert.are.equal(0, select(6, lib:GetStats()))
        assert.are.same({}, calls) -- the step handle was never unknown
        W.unit.player.power[0] = 0.9
        local p = lib:Watch("A", { kind = "power", unit = "player", power = 0, step = 1, points = { 301 } }, sink)
        untilLive(p)
        W.unit.player.max[0] = 2100 -- the point bar is placed again (and primes) on a live position source
        Fake.event("UNIT_MAXPOWER", "player")
        Fake.tick(20)
        assert.are.equal("live", (p:State()))
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

    -- Owner (fix round 3, "hold them too, it's consistency"): a jump 100 -> 85 whose Gray bit 0 and parity bars land a
    -- frame late is a valid cell for that frame, 84, a value the client never held. Every Gray change is held until the
    -- next frame's decode agrees, as the ring's: step watches and precision at a max of 100 or less alike; the first
    -- decode after a prime too (the jump on the prime's last push). The call comes within h:Latency() of the push.
    for _, case in ipairs({
        { "a step watch on health", { kind = "health", unit = "target", step = 1 } },
        { "exact energy (max 100)", { kind = "power", unit = "player", power = 3, precision = "point" } },
    }) do
        for _, prime in ipairs({ false, true }) do
            local name = case[1] .. (prime and ", on a prime's last push" or "")
            it("never reports a split jump's half state, 84 for 85: " .. name, function()
                W.unit.target.health, W.unit.player.power[3] = 1, 1
                local h = lib:Watch("A", case[2], sink)
                Fake.login()
                untilLive(h)
                Fake.tick(2)
                calls = {}
                local s, st = h.src, lib.barState
                local want = { { 85, 86, -1 } }
                if prime then
                    lib.reprime(s)
                    for _ = 1, 40 do
                        if lib.barPrime[s.core[1]] == 1 then
                            break
                        end
                        Fake.tick(1)
                    end
                    assert.are.equal(1, lib.barPrime[s.core[1]])
                    want = { { nil, nil, 0 }, { 85, 86, 0 } }
                end
                W.unit.target.health, W.unit.player.power[3] = 0.85, 0.85
                Fake.tick(1) -- the push
                local late = { s.core[1], s.core[8] } -- Gray bit 0 and the parity bar
                for k = 1, 2 do
                    st[late[k]] = not st[late[k]]
                end
                Fake.tick(1) -- decode: cell 84, valid, held
                for k = 1, 2 do
                    lib.fire(late[k])
                end
                local frames = 2
                while h:Get() ~= 85 and frames < 12 do
                    Fake.tick(1)
                    frames = frames + 1
                end
                assert.are.equal(4, frames) -- the push, 84 held, 85 held, 85 confirmed
                assert.is_true(frames * lib.frameSec <= h:Latency() + 1e-9, "frames " .. frames)
                Fake.tick(2)
                assert.are.same(want, calls)
                assert.are.equal(0, select(6, lib:GetStats()))
            end)
        end
    end

    -- L1645: exact energy (max 100, position) read 35, 36, 35, 36 over 4 frames after a spend in the owner's run.
    it(
        "holds a one-point change with either of its two bars late, every point both ways: never another value",
        function()
            W.unit.player.power[3] = 0
            local h = lib:Watch("A", { kind = "power", unit = "player", power = 3, precision = "point" }, sink)
            Fake.login()
            untilLive(h)
            Fake.tick(1)
            local s, st = h.src, lib.barState
            -- Moves the energy to v with the k-th of the change's bars not arrived yet: one frame holds (invalid), the
            -- late firing's frame holds (confirm hold, fix round 3), then v.
            local function half(v, k)
                local old, before = h:Exact(), {}
                for j = 1, #s.core do
                    before[j] = st[s.core[j]]
                end
                W.unit.player.power[3] = v / 100
                Fake.tick(1)
                local changed = {}
                for j = 1, #s.core do
                    if st[s.core[j]] ~= before[j] then
                        changed[#changed + 1] = s.core[j]
                    end
                end
                assert.are.equal(2, #changed) -- a Gray bit and the parity bar
                local i = changed[k]
                st[i] = not st[i]
                calls = {}
                Fake.tick(1)
                assert.are.equal(old, (h:Exact()), v)
                assert.are.same({}, calls)
                lib.fire(i)
                Fake.tick(1)
                assert.are.equal(old, (h:Exact()), v)
                Fake.tick(1)
                assert.are.equal(v, (h:Exact()), v)
            end
            for n = 0, 99 do
                half(n + 1, 1)
                half(n, 1)
                half(n + 1, 2)
                half(n, 2)
                half(n + 1, 1)
            end
            assert.are.equal(0, select(6, lib:GetStats()))
        end
    )

    it("needs the client to cross 36 three times to read 35, 36, 35, 36: a split spend and regen cannot", function()
        -- Reads A, B, A, B: each bar that tells A from B toggles between each two reads, three times after the first. A
        -- bar toggles once per change of its level (a firing lost or made up is a desync, not a read). After a spend
        -- v0 -> v1 and regen to at most v1 + 7 (the reads' 4 frames and 3 frames of lag, a point a frame: energy
        -- regenerates about one point in 6 frames), a bar toggles at most once for the spend plus once per change of
        -- its level from v1 up.
        local function level(n, bar) -- bars 0-6: the Gray bits; 7: parity
            if bar == 7 then
                return n % 2
            end
            return math.floor(lib.GRAY[n] / lib.POW2[bar]) % 2
        end
        local tell = {}
        for bar = 0, 7 do
            if level(35, bar) ~= level(36, bar) then
                tell[#tell + 1] = bar
            end
        end
        assert.are.same({ 2, 7 }, tell)
        local most = 0
        for v0 = 0, 100 do
            for v1 = 0, v0 do
                local f = level(v0, 2) ~= level(v1, 2) and 1 or 0
                for n = v1 + 1, math.min(100, v1 + 7) do
                    if level(n, 2) ~= level(n - 1, 2) then
                        f = f + 1
                    end
                end
                most = math.max(most, f)
            end
        end
        assert.are.equal(2, most) -- three toggles of Gray bit 2 need three level changes: the client went back over 36
    end)
end)
