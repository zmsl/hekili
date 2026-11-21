-- tests/LibHiddenValues/contract_spec.lua: the public surface of stages 0-1 (spec validation, handle methods, the sink
-- signature, capability answers, unproven kinds through the normal handle path) on the shipped fake client.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues contract", function()
    local Fake, W, lib, calls

    local function sink(h, lo, hi, dir, t, q)
        calls[#calls + 1] = { h = h, lo = lo, hi = hi, dir = dir, t = t, q = q }
    end

    local function untilLive(h)
        for _ = 1, 20 do
            if h:State() == "live" then
                Fake.tick(1) -- the first band: the prime's end is decoded at the start of the next frame
                return
            end
            Fake.tick(1)
        end
        error("never live: " .. tostring(h:State()))
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        calls = {}
    end)

    after_each(function()
        Fake.restore()
    end)

    it("rejects bad specs with nil, 'bad-spec: ...'", function()
        local bad = {
            { 1, { kind = "health", unit = "target", edges = { 20 } } },
            { "A", nil },
            { "A", { kind = "nope", unit = "target", edges = { 20 } } },
            { "A", { unit = "target", edges = { 20 } } },
            { "A", { kind = "health", edges = { 20 } } },
            { "A", { kind = "health", unit = "Creature-0-1-2-3-4", edges = { 20 } } },
            { "A", { kind = "health", unit = "target" } },
            { "A", { kind = "health", unit = "target", edges = { 0 } } },
            { "A", { kind = "health", unit = "target", edges = { 0.05 } } },
            { "A", { kind = "health", unit = "target", edges = { 101 } } },
            { "A", { kind = "health", unit = "target", edges = { "20" } } },
            { "A", { kind = "health", unit = "target", edges = 20 } },
            { "A", { kind = "health", unit = "target", step = 0 } },
            { "A", { kind = "power", unit = "player", power = "energy", edges = { 20 } } },
            { "A", { kind = "power", unit = "player", edges = { 20 } } },
            { "A", { kind = "health", unit = "target", power = "energy", edges = { 20 } } },
        }
        for i, b in ipairs(bad) do
            local h, err = lib:Watch(b[1], b[2], sink)
            assert.is_nil(h, i)
            assert.is_truthy(err:match("^bad%-spec: "), i)
        end
        local h, err = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, "notafunction")
        assert.is_nil(h)
        assert.is_truthy(err:match("^bad%-spec: "))
    end)

    it("builds nothing before PLAYER_LOGIN and never calls a sink inside Watch", function()
        local n = #Fake.frames
        W.unit.target = { health = 1.0 }
        local h = assert(lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink))
        assert.are.equal(n, #Fake.frames)
        assert.are.same({}, calls)
        assert.are.equal("pending", h:State())
        local lo, hi, t, q = h:Get()
        assert.is_nil(lo)
        assert.is_nil(hi)
        assert.are.equal(lib.UNKNOWN, q)
        assert.are.equal(0, lib.UNKNOWN)
        assert.are.equal(2, lib.BAND)
    end)

    it("goes pending, priming, live, and its first band has dir 0 and q BAND", function()
        W.unit.target = { health = 0.6 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50, 20, 20, 80 } }, sink)
        assert.is_true(Fake.login())
        untilLive(h)
        Fake.tick(1)
        assert.are.equal(1, #calls)
        local c = calls[1]
        assert.are.equal(h, c.h)
        assert.are.same({ 50, 80, 0, lib.BAND }, { c.lo, c.hi, c.dir, c.q })
        local lo, hi, t, q = h:Get()
        assert.are.same({ 50, 80, c.t, lib.BAND }, { lo, hi, t, q })
        assert.are.equal("live", (h:State()))
        local step, min, max = h:Domain()
        assert.are.same({ nil, 0, 100 }, { step, min, max })
        assert.is_nil(h:Exact())
        assert.is_true(h:Latency() > 0 and h:Latency() < 1)
    end)

    it("answers IsAvailable per kind and token", function()
        local function av(kind, unit)
            return { lib:IsAvailable(kind, unit) }
        end
        assert.are.same({ false, "pending" }, av("health", "target"))
        Fake.login()
        assert.are.same({ true, "ready" }, av("health", "target"))
        assert.are.same({ true, "ready" }, av("health", "player"))
        assert.are.same({ true, "ready" }, av("health"))
        assert.are.same({ true, "ready" }, av("power", "player"))
        assert.are.same({ false, "unavailable", "unproven" }, av("health", "focus"))
        assert.are.same({ false, "unavailable", "unproven" }, av("power", "target"))
        for _, k in ipairs({
            "cooldown",
            "charges",
            "cast",
            "totem",
            "loc",
            "bool",
            "aura",
            "threat",
            "absorb",
            "meter",
        }) do
            assert.are.same({ false, "unavailable", "unproven" }, av(k), k)
        end
        assert.are.same({ false, "unavailable", "unknown-kind" }, av("bogus"))
    end)

    it("returns handles for unproven kinds, tokens, power types and options", function()
        Fake.login()
        local specs = {
            { kind = "aura", unit = "target", spell = 1079, what = "left", edges = { 3 } },
            { kind = "cooldown", spell = 1766 },
            { kind = "health", unit = "focus", edges = { 20 } },
            { kind = "power", unit = "player", power = Enum.PowerType.Rage, edges = { 20 } },
            { kind = "power", unit = "player", power = Enum.PowerType.Energy, points = true, edges = { 20 } },
            { kind = "health", unit = "target", step = 1 },
        }
        for i, spec in ipairs(specs) do
            local h = assert(lib:Watch("A", spec, sink), i)
            assert.are.same({ "unavailable", "unproven" }, { h:State() }, i)
        end
        Fake.tick(10)
        assert.are.same({}, calls)
    end)

    it("grants edges and drops a step it cannot serve yet", function()
        W.unit.target = { health = 0.3 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 }, step = 1 }, sink)
        Fake.login()
        untilLive(h)
        assert.are.same({ nil, 0, 100 }, { h:Domain() })
        assert.are.same({ 20, 100 }, lohi(h))
    end)

    it("pulls without a sink, swaps sinks, and stops after Release", function()
        W.unit.target = { health = 0.6 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } })
        Fake.login()
        untilLive(h)
        assert.are.same({ 50, 100 }, lohi(h))
        h:SetSink(sink)
        W.unit.target.health = 0.4
        Fake.tick(2)
        assert.are.equal(1, #calls)
        assert.are.same({ 0, 50, -1 }, { calls[1].lo, calls[1].hi, calls[1].dir })
        h:Release()
        assert.are.equal("released", (h:State()))
        assert.is_nil((h:Get()))
        W.unit.target.health = 0.9
        Fake.tick(3)
        assert.are.equal(1, #calls)
    end)

    it("pauses a handle (one unknown call, no feeding) and resumes it primed", function()
        W.unit.target = { health = 0.6 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
        Fake.login()
        untilLive(h)
        Fake.tick(1)
        calls = {}
        h:SetPaused(true)
        assert.are.same({}, calls)
        Fake.tick(1)
        assert.are.equal(1, #calls)
        assert.is_nil(calls[1].lo)
        assert.are.equal(lib.UNKNOWN, calls[1].q)
        assert.are.equal("paused", (h:State()))
        local pushes = lib.nPush
        Fake.tick(5)
        assert.are.equal(pushes, lib.nPush)
        h:SetPaused(false)
        untilLive(h)
        Fake.tick(1)
        assert.are.equal(2, #calls)
        assert.are.same({ 50, 100, 0 }, { calls[2].lo, calls[2].hi, calls[2].dir })
    end)

    it("keeps a raising sink registered and reports it once", function()
        W.unit.target = { health = 0.6 }
        local n = 0
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, function()
            n = n + 1
            error("consumer bug")
        end)
        Fake.login()
        untilLive(h)
        Fake.tick(1)
        W.unit.target.health = 0.4
        Fake.tick(2)
        assert.are.equal(2, n)
        assert.are.equal(1, #Fake.errors)
        assert.are.equal("live", (h:State()))
    end)

    it("releases every handle of an owner", function()
        W.unit.target = { health = 0.6 }
        local a = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
        local b = lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 50 } }, sink)
        local c = lib:Watch("B", { kind = "health", unit = "player", edges = { 50 } }, sink)
        Fake.login()
        lib:ReleaseAll("A")
        assert.are.equal("released", (a:State()))
        assert.are.equal("released", (b:State()))
        assert.are_not.equal("released", (c:State()))
    end)

    it("reports its version", function()
        local major, minor = lib:GetVersion()
        assert.are.equal("LibHiddenValues-1.0", major)
        assert.are.equal(1, minor)
    end)
end)
