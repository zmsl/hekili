-- tests/LibHiddenValues/edges_spec.lua: named edges on the fake client: crossings both ways, the frame rules (one call
-- per handle per frame, a one-bar handle called in the frame of the push, several bars one frame later), the inclusive
-- step under every snap mode, priming and re-priming on a unit change, death.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end

describe("LibHiddenValues edges", function()
    local Fake, W, lib, calls

    local function sink(h, lo, hi, dir, t, q)
        calls[#calls + 1] = { lo = lo, hi = hi, dir = dir, t = t, q = q }
    end

    local function untilLive(h)
        for _ = 1, 20 do
            if h:State() == "live" then
                Fake.tick(1)
                calls = {}
                return
            end
            Fake.tick(1)
        end
        error("never live: " .. tostring(h:State()))
    end

    local function band(c)
        return { c.lo, c.hi, c.dir }
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        calls = {}
        W.unit.target = { health = 1.0 }
    end)

    after_each(function()
        Fake.restore()
    end)

    it("calls a one-edge handle in the frame of the push, both directions", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target.health = 0.19
        Fake.tick(1)
        assert.are.equal(1, #calls)
        assert.are.same({ 0, 20, -1 }, band(calls[1]))
        assert.are.equal(GetTime(), calls[1].t)
        assert.are.equal(lib.BAND, calls[1].q)
        W.unit.target.health = 0.2
        Fake.tick(1)
        assert.are.equal(2, #calls)
        assert.are.same({ 20, 100, 1 }, band(calls[2]))
        Fake.tick(5)
        assert.are.equal(2, #calls)
    end)

    it("nets a multi-edge jump in one frame to one call, one frame later", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target.health = 0.1
        Fake.tick(1)
        assert.are.equal(0, #calls)
        Fake.tick(1)
        assert.are.equal(1, #calls)
        assert.are.same({ 0, 20, -1 }, band(calls[1]))
        W.unit.target.health = 0.65 -- a heal over two edges
        Fake.tick(2)
        assert.are.equal(2, #calls)
        assert.are.same({ 50, 80, 1 }, band(calls[2]))
        W.unit.target.health = 1.0
        Fake.tick(2)
        assert.are.same({ 80, 100, 1 }, band(calls[3]))
        assert.are.equal(3, #calls)
    end)

    it("makes no call for a hit and a heal inside one frame", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target.health = 0.3
        W.unit.target.health = 0.9
        Fake.tick(3)
        assert.are.equal(0, #calls)
    end)

    for _, snap in ipairs({ "left", "right", "nearest" }) do
        it("puts the step on the threshold, inclusive, with snap " .. snap, function()
            Fake.set("snap", snap)
            W.unit.target.health = 0.5
            local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
            Fake.login()
            untilLive(h)
            assert.are.same({ 50, 100 }, lohi(h))
            W.unit.target.health = 0.499
            Fake.tick(1)
            assert.are.same({ 0, 50 }, lohi(h))
            W.unit.target.health = 0.5
            Fake.tick(1)
            assert.are.same({ 50, 100 }, lohi(h))
        end)
    end

    it("reports 100 as inclusive at the top", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 100 } }, sink)
        Fake.login()
        untilLive(h)
        assert.are.same({ 100, 100 }, lohi(h))
        W.unit.target.health = 0.99
        Fake.tick(1)
        assert.are.same({ 0, 100 }, lohi(h))
    end)

    it("delivers a prime that ends below the edge from the decode, and a firing that frame one frame later", function()
        W.unit.target.health = 0.1
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink)
        Fake.login()
        for _ = 1, 20 do
            if lib.stateOf(h) == "live" then -- the bars, not the public state: the first band is not decoded yet
                break
            end
            Fake.tick(1)
        end
        -- the live push left the bar below: the next frame's decode delivers the first band; the same frame's push
        -- then crosses up, and its firing may not make a second call in that frame
        W.unit.target.health = 0.5
        Fake.tick(1)
        assert.are.equal(1, #calls)
        assert.are.same({ 0, 20, 0 }, band(calls[1]))
        Fake.tick(1)
        assert.are.equal(2, #calls)
        assert.are.same({ 20, 100, 1 }, band(calls[2]))
        assert.is_true(calls[2].t > calls[1].t)
    end)

    it("re-primes on a target change: unknown once, then the new band with dir 0", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50 } }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target = { health = 0.1 }
        Fake.event("PLAYER_TARGET_CHANGED")
        assert.are.same({}, calls)
        Fake.tick(1)
        assert.are.equal(1, #calls)
        assert.is_nil(calls[1].lo)
        assert.are.same({ 0, lib.UNKNOWN }, { calls[1].dir, calls[1].q })
        assert.are.equal("priming", (h:State()))
        for _ = 1, 10 do
            Fake.tick(1)
        end
        assert.are.equal(2, #calls)
        assert.are.same({ 0, 20, 0 }, band(calls[2]))
    end)

    it("ignores the bars' own layout and hold firings while priming (lag 1 too)", function()
        Fake.set("lag", 1)
        W.unit.target.health = 0.6
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } }, sink)
        Fake.login()
        for _ = 1, 20 do
            Fake.tick(1)
        end
        assert.are.same({ 50, 80 }, lohi(h))
        W.unit.target.health = 0.1
        Fake.tick(4)
        assert.are.same({ 0, 20 }, lohi(h))
    end)

    it("goes gone with no target or a plainly dead one, and stops feeding", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target.dead = true
        W.unit.target.health = 0
        Fake.event("UNIT_HEALTH", "target")
        Fake.tick(1)
        assert.are.equal("gone", (h:State()))
        assert.are.equal(1, #calls)
        assert.is_nil(calls[1].lo)
        W.unit.target = nil
        Fake.event("PLAYER_TARGET_CHANGED")
        local pushes = lib.nPush
        Fake.tick(5)
        assert.are.equal(pushes, lib.nPush)
        assert.are.equal("gone", (h:State()))
        assert.are.equal(1, #calls)
        assert.is_nil(lib.drv:GetScript("OnUpdate"))
    end)

    it("keeps banding a dead target whose death is secret (the dead bar is a later stage)", function()
        W.secretBool = true
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target.dead = true
        W.unit.target.health = 0
        Fake.event("UNIT_HEALTH", "target")
        Fake.tick(2)
        assert.are.equal("live", (h:State()))
        assert.are.same({ 0, 20 }, lohi(h))
    end)

    it("bands mana and energy, each by its named type whatever power is displayed", function()
        W.unit.player.powerType = Enum.PowerType.Energy
        W.unit.player.power = { [0] = 0.9, [1] = 0.0, [3] = 0.1 }
        local h, err = lib:Watch("A", { kind = "power", unit = "player", edges = { 50 } })
        assert.is_nil(h)
        assert.are.equal(lib.ERR.POWER_REQUIRED, err)
        local mana = lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 50 } })
        local energy =
            lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Energy, edges = { 50 } })
        Fake.login()
        untilLive(mana)
        untilLive(energy)
        assert.are.same({ 50, 100 }, lohi(mana))
        assert.are.same({ 0, 50 }, lohi(energy))
        W.unit.player.powerType = Enum.PowerType.Mana -- a form change: the energy handle stays energy
        Fake.event("UNIT_DISPLAYPOWER", "player")
        Fake.tick(10)
        assert.are.same({ 0, 50 }, lohi(energy))
        assert.are.equal("live", (energy:State()))
        W.unit.player.power[3] = 0.7
        Fake.tick(1)
        assert.are.same({ 50, 100 }, lohi(energy))
        assert.are.same({ 50, 100 }, lohi(mana))
    end)

    it("bands rage on the player: at 0 a known lowest band first, then both ways; focus stays unproven", function()
        W.unit.player.power[Enum.PowerType.Rage] = 0
        local h = lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Rage, edges = { 30 } }, sink)
        local focus = lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Focus, edges = { 30 } })
        assert.are.same({ "unavailable", "unproven" }, { focus:State() })
        Fake.login()
        Fake.tick(10)
        assert.are.equal("live", (h:State()))
        local known = {}
        for k = 1, #calls do
            if calls[k].lo ~= nil then
                known[#known + 1] = band(calls[k])
            end
        end
        assert.are.same({ { 0, 30, 0 } }, known)
        calls = {}
        W.unit.player.power[Enum.PowerType.Rage] = 0.45
        Fake.tick(1)
        assert.are.same({ { 30, 100, 1 } }, { band(calls[1]) })
        W.unit.player.power[Enum.PowerType.Rage] = 0.1 -- decay out of combat
        Fake.tick(1)
        assert.are.same({ 0, 30, -1 }, band(calls[2]))
        assert.are.same({ "unavailable", "unproven" }, { focus:State() })
    end)

    it("stamps a several-edge call with the time of the frame the change was seen, a joining one with now", function()
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50 } }, sink)
        Fake.login()
        untilLive(h)
        W.unit.target.health = 0.4
        Fake.tick(1) -- pushed and fired
        local seen = GetTime()
        assert.are.equal(0, #calls)
        Fake.tick(1) -- decoded
        assert.are.equal(1, #calls)
        assert.are.equal(seen, calls[1].t)
        assert.are.equal(seen, select(3, h:Get()))
        Fake.tick(10)
        lib:Watch("B", { kind = "health", unit = "target", edges = { 20, 50 } }, sink) -- no new bar
        Fake.tick(1)
        assert.are.equal(2, #calls)
        assert.are.equal(GetTime(), calls[2].t)
    end)

    for _, ev in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "LOADING_SCREEN_DISABLED" }) do
        it("re-primes a fed source on " .. ev .. ", correcting a stray firing", function()
            W.unit.target.health = 0.6
            local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
            Fake.login()
            untilLive(h)
            assert.are.same({ 50, 100 }, lohi(h))
            Fake.tick(1) -- a frame without a call: the stray firing's call is not held back
            local clip = lib.barClip[h.src.bar[50]]
            clip:GetScript("OnSizeChanged")(clip) -- a re-layout fires the clip with no fill change
            assert.are.same({ 0, 50 }, lohi(h)) -- inverted
            Fake.event(ev)
            assert.are.equal("priming", (h:State()))
            untilLive(h)
            assert.are.same({ 50, 100 }, lohi(h))
            W.unit.target.health = 0.4
            Fake.tick(1)
            assert.are.same({ 0, 50, -1 }, band(calls[#calls]))
            assert.are.equal(0, lib.desyncs)
        end)
    end
end)
