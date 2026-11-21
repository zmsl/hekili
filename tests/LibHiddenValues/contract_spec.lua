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

    it("rejects bad specs with nil and an error code from lib.ERR", function()
        local E = lib.ERR
        local bad = {
            { 1, { kind = "health", unit = "target", edges = { 20 } }, E.OWNER_INVALID },
            { "A", nil, E.SPEC_INVALID },
            { "A", { kind = "nope", unit = "target", edges = { 20 } }, E.KIND_INVALID },
            { "A", { unit = "target", edges = { 20 } }, E.KIND_INVALID },
            { "A", { kind = "health", edges = { 20 } }, E.UNIT_INVALID },
            { "A", { kind = "health", unit = "Creature-0-1-2-3-4", edges = { 20 } }, E.UNIT_INVALID },
            { "A", { kind = "health", unit = "target" }, E.EDGES_REQUIRED },
            { "A", { kind = "health", unit = "target", edges = {} }, E.EDGES_REQUIRED },
            { "A", { kind = "health", unit = "target", edges = { 0 } }, E.EDGES_OUT_OF_RANGE },
            { "A", { kind = "health", unit = "target", edges = { 0.05 } }, E.EDGES_OUT_OF_RANGE },
            { "A", { kind = "health", unit = "target", edges = { 101 } }, E.EDGES_OUT_OF_RANGE },
            { "A", { kind = "health", unit = "target", edges = { "20" } }, E.EDGES_INVALID },
            { "A", { kind = "health", unit = "target", edges = 20 }, E.EDGES_INVALID },
            { "A", { kind = "health", unit = "target", step = 0 }, E.STEP_INVALID },
            { "A", { kind = "health", unit = "target", step = "1" }, E.STEP_INVALID },
            { "A", { kind = "power", unit = "player", power = "energy", edges = { 20 } }, E.POWER_INVALID },
            { "A", { kind = "power", unit = "player", edges = { 20 } }, E.POWER_REQUIRED },
            { "A", { kind = "health", unit = "target", power = "energy", edges = { 20 } }, E.POWER_INVALID },
        }
        for i, b in ipairs(bad) do
            local h, err = lib:Watch(b[1], b[2], sink)
            assert.is_nil(h, i)
            assert.is_string(b[3], i)
            assert.are.equal(b[3], err, i)
        end
        local h, err = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, "notafunction")
        assert.is_nil(h)
        assert.are.equal(E.SINK_INVALID, err)
    end)

    it("names its error codes as plain strings", function()
        local want = {
            OWNER_INVALID = "owner-invalid",
            SPEC_INVALID = "spec-invalid",
            SINK_INVALID = "sink-invalid",
            KIND_INVALID = "kind-invalid",
            UNIT_INVALID = "unit-invalid",
            EDGES_INVALID = "edges-invalid",
            EDGES_OUT_OF_RANGE = "edges-out-of-range",
            EDGES_REQUIRED = "edges-required",
            STEP_INVALID = "step-invalid",
            POWER_REQUIRED = "power-required",
            POWER_INVALID = "power-invalid",
            SPELL_INVALID = "spell-invalid",
            WHAT_INVALID = "what-invalid",
            MAX_INVALID = "max-invalid",
        }
        for k, v in pairs(want) do
            assert.are.equal(v, lib.ERR[k], k)
        end
    end)

    it("looks up messages for codes, states and reasons in enUS only", function()
        for _, code in pairs(lib.ERR) do
            assert.is_string(lib:GetMessage(code), code)
            assert.is_string(lib:GetMessage(code, "enUS"), code)
            assert.is_nil(lib:GetMessage(code, "deDE"), code)
        end
        for _, s in ipairs({ "live", "priming", "pending", "gone", "paused", "suspended", "unavailable", "released" }) do
            assert.is_string(lib:GetMessage(s), s)
        end
        for _, r in ipairs({ "ready", "api", "selftest", "error", "off", "unproven", "unknown-kind", "bad-spec" }) do
            assert.is_string(lib:GetMessage(r), r)
        end
        for _, r in ipairs({ "cdm-off", "not-in-cdm", "cdm-not-tracked", "cdm-icon-only" }) do -- the aura kind's
            assert.is_string(lib:GetMessage(r), r)
        end
        assert.is_nil(lib:GetMessage("no-such-code"))
        assert.is_nil(lib:GetMessage(nil))
        _G.GetLocale = function()
            return "frFR"
        end
        assert.is_nil(lib:GetMessage(lib.ERR.UNIT_INVALID)) -- the default locale is the client's
    end)

    it("reports 0 us per frame once nothing is fed (the self-test's frames count while it runs)", function()
        W.unit.target = { health = 0.6 }
        Fake.login()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } })
        Fake.tick(20)
        h:Release()
        Fake.tick(3)
        local bars, us, peak, push = lib:GetStats()
        assert.are.same({ 0, 0, 0 }, { bars, us, peak })
        assert.are.equal(0, push)
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
            "threat",
            "absorb",
            "meter",
        }) do
            assert.are.same({ false, "unavailable", "unproven" }, av(k), k)
        end
        assert.are.same({ true, "ready" }, av("aura"))
        assert.are.same({ false, "unavailable", "unproven" }, av("aura", "focus"))
        assert.are.same({ false, "unavailable", "unknown-kind" }, av("bogus"))
    end)

    it("returns handles for unproven kinds, tokens, power types and options", function()
        Fake.login()
        local specs = {
            { kind = "aura", unit = "focus", spell = 1079, what = "left", edges = { 3 } },
            { kind = "cooldown", spell = 1766 },
            { kind = "health", unit = "focus", edges = { 20 } },
            { kind = "power", unit = "player", power = Enum.PowerType.Focus, edges = { 20 } },
            { kind = "health", unit = "player", points = { 300 } },
        }
        for i, spec in ipairs(specs) do
            local h = assert(lib:Watch("A", spec, sink), i)
            assert.are.same({ "unavailable", "unproven" }, { h:State() }, i)
        end
        Fake.tick(10)
        assert.are.same({}, calls)
    end)

    it("grants a step beside edges as the 1% step (any step asked: 1)", function()
        W.unit.target = { health = 0.3 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 }, step = 1 }, sink)
        local five = lib:Watch("A", { kind = "health", unit = "target", step = 5 }, sink)
        Fake.login()
        untilLive(h)
        assert.are.same({ 1, 0, 100 }, { h:Domain() })
        assert.are.same({ 1, 0, 100 }, { five:Domain() })
        assert.are.same({ 30, 31 }, lohi(h))
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
        assert.are.equal(4, minor)
    end)
end)
