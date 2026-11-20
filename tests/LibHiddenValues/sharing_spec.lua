-- tests/LibHiddenValues/sharing_spec.lua: one source per canonical key, bars reference counted per edge, each handle a
-- view cut by its own edges, and a consumer joining a live source never blinds the others.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues sharing", function()
    local Fake, W, lib, log

    local function sinkFor(name)
        return function(h, lo, hi, dir)
            log[#log + 1] = { name, lo, hi, dir }
        end
    end

    local function bars()
        return (lib:GetStats())
    end

    local function settle()
        for _ = 1, 12 do
            Fake.tick(1)
        end
        log = {}
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        log = {}
        W.unit.target = { health = 0.6 }
        Fake.login()
    end)

    after_each(function()
        Fake.restore()
    end)

    it("shares one bar per edge across handles and frees it with the last reference", function()
        assert.are.equal(0, bars())
        local a = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sinkFor("a"))
        local b = lib:Watch("B", { kind = "health", unit = "target", edges = { 20, 50 } }, sinkFor("b"))
        Fake.tick(1)
        assert.are.equal(2, bars())
        local c = lib:Watch("C", { kind = "health", unit = "target", predicted = false, edges = { 20 } })
        Fake.tick(1)
        assert.are.equal(3, bars()) -- another key: its own bar
        a:Release()
        assert.are.equal(3, bars())
        b:Release()
        assert.are.equal(1, bars())
        c:Release()
        assert.are.equal(0, bars())
    end)

    it("stops at the bar cap: the handle is suspended, unfed, and its release frees every bar", function()
        local edges = {}
        for k = 1, 300 do
            edges[k] = k / 3
        end
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = edges })
        Fake.tick(2)
        assert.are.equal(256, bars())
        assert.are.equal("suspended", (h:State()))
        assert.is_nil((h:Get()))
        local pushes = lib.nPush
        Fake.tick(3)
        assert.are.equal(pushes, lib.nPush) -- a suspended handle's bars are not pushed
        local pass, lines
        lib:SelfTest(function(p, l)
            pass, lines = p, l
        end)
        assert.is_false(pass) -- no free bar: reported, the earlier verdict stands
        assert.truthy(lines[1]:find("no free bar", 1, true))
        assert.are.same({ true, "ready" }, { lib:IsAvailable("health") })
        assert.are.equal("suspended", (h:State()))
        h:Release()
        assert.are.equal(0, bars())
    end)

    it("cuts each handle's band by its own edges", function()
        local a = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sinkFor("a"))
        local b = lib:Watch("B", { kind = "health", unit = "target", edges = { 50 } }, sinkFor("b"))
        settle()
        assert.are.same({ 20, 100 }, lohi(a))
        assert.are.same({ 50, 100 }, lohi(b))
        W.unit.target.health = 0.3
        Fake.tick(2)
        assert.are.same({ { "b", 0, 50, -1 } }, log)
        W.unit.target.health = 0.1
        Fake.tick(2)
        assert.are.same({ "a", 0, 20, -1 }, log[2])
        assert.are.equal(2, #log)
    end)

    it("primes only the new bar when a consumer joins a live source", function()
        local a = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sinkFor("a"))
        settle()
        local b = lib:Watch("B", { kind = "health", unit = "target", edges = { 20, 50 } }, sinkFor("b"))
        for _ = 1, 8 do
            Fake.tick(1)
            assert.are.equal("live", (a:State()))
        end
        assert.are.same({ { "b", 50, 100, 0 } }, log)
        assert.are.same({ 50, 100 }, lohi(b))
    end)

    it("keeps feeding a shared source while one of its handles is paused", function()
        local a = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sinkFor("a"))
        local b = lib:Watch("B", { kind = "health", unit = "target", edges = { 50 } }, sinkFor("b"))
        settle()
        a:SetPaused(true)
        W.unit.target.health = 0.3
        Fake.tick(2)
        assert.are.same({ { "a", nil, nil, 0 }, { "b", 0, 50, -1 } }, log)
        assert.are.equal("live", (b:State()))
    end)
end)
