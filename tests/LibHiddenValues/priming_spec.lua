-- tests/LibHiddenValues/priming_spec.lua: a prime reports unknown until its band is settled, then the true band once
-- with dir 0 (LHVProbe 2026-11-20: a live push's firing came one frame after the decode that followed it, so every
-- prime reported the lowest band for a frame, then the real one with dir 1). Every firing delay the settle window
-- covers, one edge and several, a new watch, the login, a target change, a value below every edge.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

describe("LibHiddenValues priming", function()
    local Fake, W, lib, calls

    local function sink(h, lo, hi, dir)
        calls[#calls + 1] = { lo = lo, hi = hi, dir = dir }
    end

    -- Every call is unknown until the one known call, the expected band with dir 0.
    local function firstBand(lo, hi)
        Fake.tick(30)
        local known = {}
        for k = 1, #calls do
            if calls[k].lo ~= nil then
                known[#known + 1] = { calls[k].lo, calls[k].hi, calls[k].dir }
            end
        end
        assert.are.same({ { lo, hi, 0 } }, known)
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        calls = {}
        W.unit.target = { health = 0.6 }
    end)

    after_each(function()
        Fake.restore()
    end)

    for delay = 0, 4 do
        local function delayed()
            Fake.set("secretlag", delay > 0 and 1 or 0)
            Fake.set("lag", delay > 0 and delay - 1 or 0)
        end

        describe("with firings " .. delay .. " frames late", function()
            it("gives a new several-edge watch its true band first", function()
                Fake.login()
                delayed()
                lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } }, sink)
                firstBand(50, 80)
            end)

            it("gives a new one-edge watch its true band first", function()
                Fake.login()
                delayed()
                lib:Watch("A", { kind = "health", unit = "player", edges = { 50 } }, sink)
                firstBand(50, 100)
            end)

            it("gives a watch made before login its true band first", function()
                delayed()
                lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } }, sink)
                Fake.login()
                firstBand(50, 80)
            end)

            it("gives a power watch sitting below its only edge its true band first", function()
                W.unit.player.power[0] = 0
                Fake.login()
                delayed()
                lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 30 } }, sink)
                firstBand(0, 30)
            end)

            it("gives the new target its true band first", function()
                Fake.login()
                delayed()
                local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } }, sink)
                Fake.tick(30)
                local lo, hi = h:Get()
                assert.are.same({ 50, 80 }, { lo, hi })
                calls = {}
                W.unit.target = { health = 0.9 }
                Fake.event("PLAYER_TARGET_CHANGED")
                firstBand(80, 100)
                assert.is_nil(calls[1].lo) -- unknown once first
            end)
        end)
    end

    -- "live" means a band is known: State() never says "live" while Get() is nil, checked after every frame.
    for lag = 0, 1 do
        describe("with secret firings " .. lag .. " frames late", function()
            local function neverLiveUnknown(hs, frames)
                for f = 0, frames do
                    if f > 0 then
                        Fake.tick(1)
                    end
                    for k = 1, #hs do
                        local h = hs[k]
                        assert.is_false(h:State() == "live" and h:Get() == nil, "handle " .. k .. ", frame " .. f)
                    end
                end
                for k = 1, #hs do
                    assert.are.equal("live", (hs[k]:State()), "handle " .. k)
                end
            end

            before_each(function()
                Fake.login()
                Fake.set("secretlag", lag)
            end)

            it("says live only with a band, across a prime of one edge above, one below and several edges", function()
                W.unit.player.power[0] = 0
                local above = lib:Watch("A", { kind = "health", unit = "player", edges = { 50 } })
                local below =
                    lib:Watch("A", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 30 } })
                local several = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } })
                neverLiveUnknown({ above, below, several }, 20)
                W.unit.target = { health = 0.9 }
                Fake.event("PLAYER_TARGET_CHANGED")
                neverLiveUnknown({ above, below, several }, 20)
            end)

            it("says live only with a band for a joiner on a shared live source", function()
                local a = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50 } })
                Fake.tick(20)
                local b = lib:Watch("B", { kind = "health", unit = "target", edges = { 20, 50 } })
                neverLiveUnknown({ a, b }, 5)
            end)
        end)
    end
end)
