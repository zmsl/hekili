-- tests/LibHiddenValues/aura_timing_spec.lua: the aura kind's answers over time (review round 1). An absent aura is a
-- known value (no stacks, no seconds: the lowest band, "live"); a bar is never decoded in the frame of its first push
-- (the first band after a prime is the true one, dir 0, once), also with secret firings a frame late; State() never
-- says "live" while Get() is nil; a data change that keeps the item counts is seen (a newly placed aura answers, a
-- removed one too) and a lost item is not searched every frame; an errored kind's hooks stop at once; IsAvailable never
-- calls a capability callback.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

-- cooldownIDs 11, 12, 15 name spells 5001, 5002, 5005: 11 and 15 tracked bars, 12 an icon.
local CATALOGUE = {
    [11] = { spellID = 5001, category = 3 },
    [12] = { spellID = 5002, category = 2 },
    [15] = { spellID = 5005, category = 3 },
}

describe("LibHiddenValues aura timing", function()
    local Fake, W, lib, calls

    local function sink(h, lo, hi, dir)
        calls[#calls + 1] = { h = h, lo = lo, hi = hi, dir = dir }
    end

    local function band(h)
        local lo, hi = h:Get()
        return { lo, hi }
    end

    -- The known calls of handle h, as { lo, hi, dir }.
    local function known(h)
        local out = {}
        for k = 1, #calls do
            local c = calls[k]
            if c.h == h and c.lo ~= nil then
                out[#out + 1] = { c.lo, c.hi, c.dir }
            end
        end
        return out
    end

    local function boot(bar)
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        W.cdm.catalogue = CATALOGUE
        W.cdm.bar = bar or { 11, 15 }
        W.cdm.icon = { 12 }
        calls = {}
    end

    local function watch(spec)
        spec.kind = "aura"
        spec.unit = spec.unit or "player"
        return assert(lib:Watch("A", spec, sink))
    end

    after_each(function()
        assert.are.same({}, Fake.errors)
        assert.are.same({}, Fake.touched)
        Fake.restore()
    end)

    it("reads an absent aura as no stacks and no seconds: the lowest band, live", function()
        boot()
        local s = watch({ spell = 5001, what = "stacks", edges = { 2, 4 } })
        local exact = watch({ spell = 5001, what = "stacks", max = 3 })
        local l = watch({ spell = 5001, what = "left", edges = { 3, 6 } })
        Fake.login()
        W.combat = true
        Fake.tick(20)
        assert.are.same({ "live", 0, 2 }, { s:State(), band(s)[1], band(s)[2] })
        assert.are.same({ 0, 1 }, band(exact))
        assert.are.same({ "live", 0, 3 }, { l:State(), band(l)[1], band(l)[2] })
        calls = {}
        Fake.setAura("player", 5001, 1, 9) -- one stack: the client hides the count
        Fake.tick(10)
        assert.are.same({}, known(s)) -- still below 2
        assert.are.same({ { 1, 2, 1 } }, known(exact))
        assert.are.same({ { 6, math.huge, 1 } }, known(l))
        calls = {}
        Fake.setAura("player", 5001, 3, 9)
        Fake.tick(10)
        assert.are.same({ { 2, 4, 1 } }, known(s))
        assert.are.same({ { 3, 3, 1 } }, known(exact))
        calls = {}
        Fake.setAura("player", 5001, nil)
        Fake.tick(10)
        assert.are.same({ { 0, 2, -1 } }, known(s))
        assert.are.same({ { 0, 1, -1 } }, known(exact))
        assert.are.same({ { 0, 3, -1 } }, known(l))
        for _, h in ipairs({ s, exact, l }) do
            assert.are.equal("live", (h:State()))
        end
    end)

    for lag = 0, 1 do
        describe("with secret firings " .. lag .. " frames late", function()
            local function settle()
                Fake.login()
                W.combat = true
                Fake.set("secretlag", lag)
                Fake.tick(20)
            end

            it("gives a stacks watch made while the aura is up its true band first, once", function()
                boot()
                Fake.setAura("player", 5001, 3)
                settle()
                local h = watch({ spell = 5001, what = "stacks", edges = { 2 } })
                Fake.tick(20)
                assert.are.same({}, known(h)) -- no count written since the watch: unknown
                Fake.setAura("player", 5001, 4)
                Fake.tick(20)
                assert.are.same({ { 2, math.huge, 0 } }, known(h))
            end)

            it("gives a seconds watch made while the aura is up its true band first, once", function()
                boot()
                Fake.setAura("player", 5001, 1, 30)
                settle()
                local h = watch({ spell = 5001, what = "left", edges = { 3, 6 } })
                Fake.tick(20)
                assert.are.same({ { 6, math.huge, 0 } }, known(h))
            end)

            it("gives the first application its true band, not the lowest then the real one", function()
                boot()
                local h = watch({ spell = 5001, what = "left", edges = { 3 } })
                settle()
                calls = {}
                Fake.setAura("player", 5001, 1, 9)
                Fake.tick(20)
                assert.are.same({ { 3, math.huge, 1 } }, known(h))
            end)

            it("keeps the band over a layout pass while the aura is up", function()
                boot()
                Fake.setAura("player", 5001, 3, 30)
                local s = watch({ spell = 5001, what = "stacks", edges = { 2 } })
                local l = watch({ spell = 5001, what = "left", edges = { 3 } })
                settle()
                Fake.setAura("player", 5001, 3, 30)
                Fake.tick(20)
                calls = {}
                W.cdm.shuffle = true
                Fake.cdmLayout()
                Fake.tick(20)
                assert.are.same({}, calls)
                assert.are.same({ 2, math.huge }, band(s))
                assert.are.same({ 3, math.huge }, band(l))
            end)

            it("after a loading screen while the aura is up: unknown, then the true band once with dir 0", function()
                boot()
                Fake.setAura("player", 5001, 3, 30)
                local l = watch({ spell = 5001, what = "left", edges = { 3 } })
                local s = watch({ spell = 5001, what = "stacks", edges = { 2 } })
                settle()
                Fake.setAura("player", 5001, 3, 30)
                Fake.tick(20)
                calls = {}
                Fake.event("LOADING_SCREEN_DISABLED")
                Fake.tick(20)
                Fake.setAura("player", 5001, 3, 30) -- the count is written again
                Fake.tick(20)
                assert.is_nil(calls[1].lo)
                assert.are.same({ { 3, math.huge, 0 } }, known(l))
                assert.are.same({ { 2, math.huge, 0 } }, known(s))
            end)

            it("says live only with a band", function()
                boot()
                local hs = {
                    watch({ spell = 5001, what = "stacks", edges = { 2, 4 } }),
                    watch({ spell = 5001, what = "left", edges = { 3 } }),
                    watch({ spell = 5001, what = "up" }),
                    watch({ unit = "target", spell = 5002, what = "stacks", max = 3 }),
                }
                Fake.login()
                W.combat = true
                Fake.set("secretlag", lag)
                local function check(frames)
                    for f = 1, frames do
                        Fake.tick(1)
                        for k = 1, #hs do
                            local h = hs[k]
                            assert.is_false(h:State() == "live" and h:Get() == nil, "handle " .. k .. ", frame " .. f)
                        end
                    end
                end
                check(20)
                Fake.setAura("player", 5001, 3, 4)
                Fake.setAura("target", 5002, 2)
                check(10)
                Fake.event("LOADING_SCREEN_DISABLED")
                check(10)
                hs[#hs + 1] = watch({ spell = 5001, what = "stacks", max = 5 })
                check(10)
                W.aura.target = {}
                Fake.event("PLAYER_TARGET_CHANGED")
                check(300) -- through the expiry
            end)
        end)
    end

    it(
        "sees a data change that keeps the item count: placed answers, removed answers, no rescan every frame",
        function()
            boot({ 11 }) -- one bar placed: the viewer holds its 2-item minimum
            local told = {}
            lib:OnCapability("A", function(kind, state, reason, h)
                if h then
                    told[#told + 1] = { h.spell, state, reason }
                end
            end)
            local old = watch({ spell = 5001, what = "up" })
            local new = watch({ spell = 5005, what = "up" })
            Fake.login()
            Fake.tick(4)
            assert.are.equal("live", (old:State()))
            assert.are.same({ "unavailable", "cdm-not-tracked" }, { new:State() })
            told = {}
            W.cdm.bar = { 15 }
            Fake.cdmData()
            Fake.tick(2)
            table.sort(told, function(a, b)
                return a[1] < b[1]
            end)
            assert.are.same({ { 5001, "unavailable", "cdm-not-tracked" }, { 5005, "ready" } }, told)
            Fake.tick(6)
            assert.are.equal("live", (new:State()))
            local scans = select(7, lib:GetAuraSources())
            Fake.tick(60)
            assert.is_true(select(7, lib:GetAuraSources()) - scans <= 2)
        end
    )

    it("answers a newly placed aura on a data change that keeps the item count (no item watched before)", function()
        boot({ 11 })
        local told = {}
        lib:OnCapability("A", function(_, state, reason, h)
            told[#told + 1] = { h and h.spell, state, reason }
        end)
        local new = watch({ spell = 5005, what = "up" })
        Fake.login()
        Fake.tick(4)
        told = {}
        W.cdm.bar = { 15 }
        Fake.cdmData() -- only RefreshData runs: no acquire, no event, no watched item to miss
        Fake.tick(2)
        assert.are.same({ { 5005, "ready" } }, told)
    end)

    it("follows a drag reorder (same count) with no answer change", function()
        boot({ 11, 15 })
        local told = {}
        lib:OnCapability("A", function(_, state, reason, h)
            told[#told + 1] = { h and h.spell, state, reason }
        end)
        local a = watch({ spell = 5001, what = "stacks", edges = { 2 } })
        local b = watch({ spell = 5005, what = "stacks", edges = { 2 } })
        Fake.login()
        W.combat = true
        Fake.tick(10)
        Fake.setAura("player", 5001, 3)
        Fake.setAura("player", 5005, 1)
        Fake.tick(10)
        assert.are.same({ 2, math.huge }, band(a))
        assert.are.same({ 0, 2 }, band(b))
        told = {}
        W.cdm.bar = { 15, 11 }
        Fake.cdmData()
        Fake.tick(10)
        Fake.setAura("player", 5001, 1)
        Fake.setAura("player", 5005, 3)
        Fake.tick(10)
        assert.are.same({ 0, 2 }, band(a))
        assert.are.same({ 2, math.huge }, band(b))
        assert.are.same({}, told)
    end)

    it("stops an errored kind's hooks at once", function()
        boot()
        local h = watch({ spell = 5001, what = "left", edges = { 3 } })
        Fake.login()
        Fake.tick(10)
        local changed = 0
        local base = lib.capChanged
        lib.capChanged = function()
            changed = changed + 1
            return base()
        end
        lib.cdmValue = function()
            error("a hook body that raises")
        end
        Fake.setAura("player", 5001, 1, 30) -- the tracked bar pushes every frame from now on
        Fake.tick(60)
        assert.are.equal(1, #Fake.errors)
        assert.are.equal(1, changed)
        assert.are.same({ "unavailable", "error" }, { h:State() })
        Fake.errors[1] = nil
    end)

    it("never calls a capability callback from inside IsAvailable", function()
        boot({ 11 })
        local told = 0
        lib:OnCapability("A", function()
            told = told + 1
        end)
        watch({ spell = 5005, what = "up" })
        Fake.login()
        Fake.tick(4)
        told = 0
        W.cdm.bar = { 11, 15 }
        Fake.cdmLayout()
        lib:IsAvailable("aura", { kind = "aura", unit = "player", spell = 5005, what = "up" })
        assert.are.equal(0, told)
        Fake.tick(2)
        assert.are.equal(1, told)
    end)
end)
