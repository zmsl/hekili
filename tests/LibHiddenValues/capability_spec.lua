-- tests/LibHiddenValues/capability_spec.lua: pending until the self-test, then ready; and every way a kind turns off
-- cleanly: "api" (a function missing), "selftest" (bars do not fire for plain values), "error" (a client call raises),
-- "off" (the kill switch). Each loss: one unknown call per handle, the capability callbacks, the driver unset.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues capability", function()
    local Fake, W, lib, calls, caps

    local function sink(h, lo, hi, dir, t, q)
        calls[#calls + 1] = { lo = lo, hi = hi, dir = dir, q = q }
    end

    local function untilLive(h)
        for _ = 1, 20 do
            if h:State() == "live" then
                Fake.tick(1)
                return
            end
            Fake.tick(1)
        end
        error("never live: " .. tostring(h:State()))
    end

    local function boot(opts)
        Fake = opts and loadfile(FAKE)(opts) or dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        W.unit.target = { health = 0.6 }
    end

    before_each(function()
        calls, caps = {}, {}
    end)

    after_each(function()
        Fake.restore()
    end)

    it("runs the self-test at login and reports its lines", function()
        boot()
        local got
        lib:SelfTest(function(pass, lines)
            got = { pass, lines }
        end)
        assert.is_true(Fake.login())
        assert.is_true(got[1])
        assert.is_true(#got[2] >= 2)
        for _, l in ipairs(got[2]) do
            assert.is_true(#l < 255, l)
        end
        local again
        lib:SelfTest(function(pass)
            again = pass
        end)
        assert.is_nil(again)
        Fake.tick(60)
        assert.is_true(again)
        assert.are.equal(0, (lib:GetStats()))
    end)

    it("turns everything off with reason api when the curve API is missing", function()
        boot({
            before = function()
                rawset(_G, "C_CurveUtil", nil)
            end,
        })
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink)
        Fake.tick(10)
        assert.are.same({ false, "unavailable", "api" }, { lib:IsAvailable("health") })
        assert.are.same({ "unavailable", "api" }, { h:State() })
        local verdict
        lib:SelfTest(function(pass)
            verdict = pass
        end)
        assert.is_false(verdict)
    end)

    it("turns one kind off with reason api when its read is missing", function()
        boot()
        rawset(_G, "UnitPowerPercent", nil)
        Fake.login()
        assert.are.same({ false, "unavailable", "api" }, { lib:IsAvailable("power", "player") })
        assert.are.same({ true, "ready" }, { lib:IsAvailable("health", "target") })
    end)

    it("fails the self-test when bars do not fire, and handles report it", function()
        boot()
        Fake.set("drop", 1)
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink)
        lib:OnCapability("A", function(kind, state, reason)
            caps[#caps + 1] = kind .. ":" .. state .. ":" .. tostring(reason)
        end)
        assert.is_false(Fake.login())
        assert.are.same({ "unavailable", "selftest" }, { h:State() })
        table.sort(caps)
        assert.are.same({ "health:unavailable:selftest", "power:unavailable:selftest" }, caps)
        Fake.tick(3)
        assert.is_nil(lib.drv:GetScript("OnUpdate"))
    end)

    for _, case in ipairs({ { 4, true, "1, after it 0: ok" }, { 5, false, "0, after it 1: FAIL" } }) do
        it(
            "checks a prime's firing lands in its settle window (secret firings " .. case[1] .. " frames late)",
            function()
                boot()
                Fake.set("secretlag", case[1])
                local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink)
                assert.are.equal(case[2], Fake.login())
                local _, lines = lib:GetSelfTest()
                local want = "selftest prime: firings in the settle window " .. case[3]
                assert.is_truthy(table.concat(lines, "\n"):find(want, 1, true), table.concat(lines, "\n"))
                assert.are.equal(case[2] and "priming" or "unavailable", (h:State())) -- pending until the verdict
            end
        )
    end

    it("turns a kind off for the session when its read raises, reporting the error once", function()
        boot()
        local hp = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
        local mp = lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 50 } })
        Fake.login()
        untilLive(hp)
        untilLive(mp)
        calls = {}
        Fake.set("refuse", "UnitHealthPercent")
        Fake.tick(3)
        assert.are.equal(1, #Fake.errors)
        assert.are.same({ "unavailable", "error" }, { hp:State() })
        assert.are.equal(1, #calls)
        assert.is_nil(calls[1].lo)
        assert.are.equal("live", (mp:State()))
        W.unit.player.power[0] = 0.2
        Fake.tick(3)
        assert.are.same({ 0, 50 }, lohi(mp))
        assert.are.equal(1, #Fake.errors)
    end)

    it("switches off and back on with SetEnabled", function()
        boot()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
        lib:OnCapability("A", function(kind, state, reason)
            caps[#caps + 1] = kind .. ":" .. state .. ":" .. tostring(reason)
        end)
        Fake.login()
        untilLive(h)
        calls, caps = {}, {}
        lib:SetEnabled(false)
        Fake.tick(2)
        assert.are.same({ "unavailable", "off" }, { h:State() })
        assert.are.same({ false, "unavailable", "off" }, { lib:IsAvailable("health") })
        assert.are.equal(1, #calls)
        assert.is_nil(calls[1].lo)
        assert.are.equal(0, (lib:GetStats()))
        assert.is_nil(lib.drv:GetScript("OnUpdate"))
        table.sort(caps)
        assert.are.same({ "health:unavailable:off", "power:unavailable:off" }, caps)
        lib:SetEnabled(true)
        assert.are.equal("pending", (h:State()))
        Fake.login()
        untilLive(h)
        assert.are.same({ 50, 100, 0 }, { calls[2].lo, calls[2].hi, calls[2].dir })
    end)

    it("recovers from a failed self-test through the API: SetEnabled(true) then SelfTest", function()
        boot()
        Fake.set("drop", 1)
        assert.is_false(Fake.login())
        Fake.set("drop", 0)
        lib:SetEnabled(true) -- already on: changes nothing, the failed verdict stands
        assert.are.same({ false, "unavailable", "selftest" }, { lib:IsAvailable("health") })
        local pass, lines
        lib:SelfTest(function(p, l)
            pass, lines = p, l
        end)
        Fake.tick(60)
        assert.are.same({ true, "ready" }, { lib:IsAvailable("health") })
        assert.is_true(pass)
        assert.truthy(lines[#lines]:find("selftest PASS", 1, true))
    end)

    it(
        "turns back on through SetEnabled(false), SetEnabled(true), SelfTest(fn): one PASS call, handles synced",
        function()
            boot()
            local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
            assert.is_true(Fake.login())
            untilLive(h)
            lib:SetEnabled(false)
            lib:SetEnabled(true)
            assert.are.same({ nil, nil, true }, { lib:GetSelfTest() }) -- no earlier run's lines beside a nil verdict
            local got = {}
            lib:SelfTest(function(pass, lines)
                got[#got + 1] = { pass, lines[#lines], h:State(), (lib:IsAvailable("health")) }
            end)
            Fake.tick(60)
            assert.are.equal(1, #got)
            assert.is_true(got[1][1])
            assert.truthy(got[1][2]:find("selftest PASS", 1, true))
            assert.are.equal("priming", got[1][3]) -- the sources were re-synced before the callback, not "suspended"
            assert.is_true(got[1][4])
            assert.are.equal("live", (h:State()))
        end
    )
end)
