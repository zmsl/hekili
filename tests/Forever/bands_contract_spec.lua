-- tests/Forever/bands_contract_spec.lua (LibHiddenValues integration design 5.4 item 1, lane B0): the real
-- LibHiddenValues on its own Testing/FakeClient.lua runs in one busted process beside Hekili's fake_api, the belief and
-- headless Hekili (the B0 spike). The shape the contract specs use:
--   1. dofile the FakeClient first: it installs its globals into the real _G (the library reads _G);
--   2. `api, ctl = fake_api.new()` and `ctl.LibStub = LibStub` (the FakeClient's): api.LibStub then answers the real
--      library, while fake_api's own libraries (LibRangeCheck-3.0) still come from its vendored LibStub;
--   3. the belief is loaded with fake_api's CreateFrame, GetTime and issecretvalue in _G for the load (as
--      tests/Game/State/providers_spec.lua does), so its event facade binds to fake_api, not to the FakeClient;
--   4. two clocks (fake_api's ctl.now, the FakeClient's 60 frames a second from 1000): the spec drives Fake.tick and
--      calls `sync()` (ctl.now = the library's GetTime) before every drain and every fake_api timer it lets run, or
--      the belief runs on a skewed clock;
--   5. Fake.restore() last, after any _G override of step 3 is put back.
-- In game the belief's api is the client's _G (Game/Events/EventFacade.lua `client`), so api.LibStub is the global
-- LibStub that the embed (packaged) or the standalone folder (OptionalDeps, development) loaded the library into.
local fake = require("Game.State.helpers.fake_api")
local load = require("Game.State.helpers.load")
local fs = require("Game.State.helpers.fake_spec")
local headless = require("Game.harness.headless")

local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"
local MAJOR = "LibHiddenValues-1.0"

describe("the band contract: LibHiddenValues on its FakeClient beside fake_api", function()
    local Fake, W, api, ctl, before, libTime

    before_each(function()
        before = {}
        for k in pairs(_G) do
            before[k] = true
        end
        Fake = dofile(FAKE)
        W = Fake.world
        libTime = rawget(_G, "GetTime") -- the FakeClient's clock
        api, ctl = fake.new()
        ctl.LibStub = LibStub
    end)

    local function sync() -- one clock: the library's
        ctl.now = libTime()
        return ctl.now
    end

    after_each(function()
        Fake.restore()
        local added = {}
        for k in pairs(_G) do
            if not before[k] then
                added[#added + 1] = tostring(k)
            end
        end
        assert.are.same({}, added) -- the FakeClient puts back every global it set
    end)

    it("api.LibStub answers the real library; fake_api's range library stays its own", function()
        local LHV = api.LibStub(MAJOR)
        assert.are.equal(LibStub(MAJOR), LHV)
        assert.are.equal(MAJOR, (LHV:GetVersion()))
        local lrc = api.LibStub("LibRangeCheck-3.0")
        assert.is_table(lrc)
        assert.is_nil(LibStub("LibRangeCheck-3.0", true)) -- not the FakeClient's LibStub
        assert.is_nil(api.LibStub("NoSuchLibrary-1.0", true))
        assert.has_error(function()
            api.LibStub("NoSuchLibrary-1.0")
        end)
    end)

    it("a target health watch primes: unknown until login and priming, then the true 1% cell", function()
        local LHV = api.LibStub(MAJOR)
        W.unit.target = { health = 0.537 }
        local h = assert(LHV:Watch("HekiliBelief", { kind = "health", unit = "target", step = 1 }))
        assert.is_nil((h:Get()))
        assert.are.equal("pending", (h:State()))
        assert.is_true(Fake.login())
        Fake.tick(12) -- priming: 10 frames at least (the library's README, "Testing your addon")
        sync()
        local lo, hi, t, q = h:Get()
        assert.are.same({ 53, 54, LHV.BAND }, { lo, hi, q })
        assert.is_true(t <= ctl.now)
        assert.are.equal("live", (h:State()))
        assert.is_true(h:Latency() > 0)
        h:Release()
        assert.are.equal("released", (h:State()))
    end)

    it("the belief loads and starts on fake_api with the FakeClient installed", function()
        local saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k)
            _G[k] = v
        end
        local ns = load.module()
        for k, v in pairs(saved) do
            _G[k] = v
        end
        local VS, I = ns.VirtualState, ns.VirtualStateInternal
        I.Build(fs.def(fs.new(9)), sync())
        VS.Start(api)
        assert.are.equal(api, I.api)
        assert.are.equal(LibStub(MAJOR), I.api.LibStub(MAJOR, true))
        assert.is_true(api.frame.events.PLAYER_REGEN_ENABLED ~= nil) -- the belief's frame is fake_api's
        assert.is_true(Fake.login())
        VS.Drain(sync())
        assert.are.same({}, Fake.errors)
    end)

    it(
        "headless Hekili loads with no errors and no unexpected reads with the FakeClient installed; its belief's LibStub is the client's own",
        function()
            local H = headless.new()
            assert.are.same({}, H.loadErrors)
            assert.are.same({}, headless.unexpected(H, "load"))
            assert.are.same({}, headless.unexpected(H, "login"))
            local I = H.ns.VirtualStateInternal
            assert.are.equal(H.env, I.api)
            assert.are.equal(rawget(H.env, "LibStub"), I.api.LibStub)
            assert.is_nil(I.api.LibStub(MAJOR, true)) -- the guarded embed loads nothing headless
        end
    )
end)

-- Lane B1 (integration design 2.1-2.3, 5.1-5.3): the band source, Game/State/Sources/Bands.lua, on the real library.
-- The belief on fake_api (the shape above), its def: the fake spec's rage slot (1) and a mana slot (2); the channels
-- -1 target health, 0 player health, r a resource slot. Every Obs.Band the fold reaches is recorded as "ch lo hi"
-- (health in fractions 0-1, power in points; "ch -" unknown) by a spec-side applier: no family reads the kind yet.
describe("the band source on the real library (Game/State/Sources/Bands.lua)", function()
    local alloc = require("Game.State.helpers.alloc")
    local Fake, W, api, ctl, libTime, LHV, VS, I, def, seen
    local FRAME = 1 / 60
    local MANA = 2 -- the def's mana slot

    local function sync()
        ctl.now = libTime()
        return ctl.now
    end

    -- the belief built and started on fake_api (record = false: no spec-side applier, for the allocation case)
    local function boot(record)
        local saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        local ns = load.module()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        def = fs.def(fs.new(9))
        def.resources[MANA] = { key = "mana", type = 0, token = "MANA", max = 1000 }
        def.providers = { bands = true }
        seen = {}
        if record ~= false then
            I.On(assert(VS.Obs.Band), function(o)
                seen[#seen + 1] = o.b > o.c and (o.a .. " -") or (o.a .. " " .. o.b .. " " .. o.c)
            end)
        end
        VS.Start(api)
        I.Build(def, sync())
    end

    -- n frames, a drain after each; the observations of channel `ch` (nil: every channel) per drain ("" none), "|"
    local function frames(n, ch)
        local row = {}
        for i = 1, n do
            Fake.tick(1)
            local from = #seen + 1
            VS.Drain(sync())
            local got = {}
            for j = from, #seen do
                local c, rest = seen[j]:match("^(%-?%d+) (.*)$")
                if ch == nil then
                    got[#got + 1] = seen[j]
                elseif tonumber(c) == ch then
                    got[#got + 1] = rest
                end
            end
            row[i] = table.concat(got, ",")
        end
        return table.concat(row, "|")
    end

    local function live()
        assert.is_true(Fake.login())
        frames(14)
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        W.unit.target = { health = 0.637 }
        W.unit.player.health = 0.805
        W.unit.player.power[0], W.unit.player.max[0] = 0.45, 1000
        W.unit.player.power[1] = 0.3
        libTime = rawget(_G, "GetTime")
        api, ctl = fake.new()
        ctl.LibStub = LibStub
        LHV = LibStub(MAJOR)
    end)

    after_each(function()
        Fake.restore()
    end)

    it("primes: nothing before the first band, then the true band every drain, no false lowest band; Q8", function()
        boot()
        frames(3)
        assert.are.same({}, seen) -- pending before login
        assert.is_true(Fake.login())
        local row = frames(14, -1)
        local lead, bands = row:match("^(|*)(.*)$")
        assert.is_true(#lead >= 1, row) -- unknown at first: nothing logged
        assert.are.equal(("|0.63 0.64"):rep(14 - #lead):sub(2), bands)
        assert.are.equal("0.8 0.81", frames(1, 0))
        -- Q8 (design 6.3): { step = 1, points = {} } answers the 1% grid in points
        assert.are.equal("450 460", frames(1, MANA))
        assert.are.equal("", frames(1, 1)) -- rage: paused while the client shows mana
    end)

    it("a target change: one unknown, nothing while it primes, then the new band stamped at the prime's end", function()
        boot()
        live()
        W.unit.target = { health = 0.195 }
        Fake.event("PLAYER_TARGET_CHANGED")
        local t0 = libTime()
        assert.are.equal("-||||||||||0.19 0.2|0.19 0.2|0.19 0.2", frames(13, -1))
        assert.are.near(t0 + 9 * FRAME, I.bandT[-1], 1e-9)
        assert.is_true(I.bandLive[-1])
    end)

    -- Lane B2 (design 2.6): the target health family reads the band; a swap to a low target reads full through the
    -- library's prime (no low reading on a swap), then the new band's middle.
    it("a swap to a low target: the family reads full through the prime, then the new band (lane B2)", function()
        boot()
        live()
        assert.are.near(0.635, VS.Health("target", ctl.now).est, 1e-9)
        W.unit.target = { health = 0.195 }
        ctl.guid.target = "Creature-2"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        Fake.event("PLAYER_TARGET_CHANGED")
        local reads = {}
        for i = 1, 13 do
            frames(1)
            reads[i] = ("%.3f"):format(VS.Health("target", ctl.now).est)
        end
        assert.are.equal(("1.000 "):rep(10) .. ("0.195 "):rep(3), table.concat(reads, " ") .. " ")
    end)

    -- L1666 f, decided in lane B2: a rebuild in combat (a pack switch, a /reload) releases the watches and makes none
    -- until combat ends (decision 89: no path change mid-fight); the families run today's code meanwhile.
    it(
        "a rebuild in combat: no band for the rest of the fight, the watches back at the first drain out of it",
        function()
            boot()
            live()
            ctl.Fire("PLAYER_REGEN_DISABLED")
            I.Build(def, sync())
            assert.are.equal(("|"):rep(12), frames(13, -1))
            assert.are.equal(1, VS.Health("target", ctl.now).est)
            ctl.Fire("PLAYER_REGEN_ENABLED")
            frames(13)
            assert.are.equal("0.63 0.64", frames(1, -1))
        end
    )

    it(
        "bandOff: in combat nothing changes; at PLAYER_REGEN_ENABLED one unknown per live channel, the watches released",
        function()
            boot()
            live()
            ctl.Fire("PLAYER_REGEN_DISABLED")
            def.providers.bands = false
            assert.are.equal("0.63 0.64", frames(1, -1))
            assert.is_true(#LHV:GetSources() > 0)
            ctl.Fire("PLAYER_REGEN_ENABLED")
            assert.are.equal("0 -,-1 -,2 -|", frames(2)) -- def.units order: player, target
            assert.are.same({}, LHV:GetSources())
            def.providers.bands = true
            frames(13)
            assert.are.equal("0.63 0.64", frames(1, -1))
        end
    )

    -- Design 2.1's two-cell case (L1624: another addon's point precision at a max over 3175) no longer arises at
    -- minor 7: a step watch beside a ring keeps the 8 position bars (README, `precision`), shown first on the real
    -- library; a band wider than a cell is then planted on the belief's own live handle, State still the library's.
    it("a band wider than one cell passes through as [lo, hi) untouched", function()
        W.unit.player.power[0], W.unit.player.max[0] = 3967 / 6400, 6400
        assert(LHV:Watch("Other", { kind = "power", unit = "player", power = 0, precision = "point" }))
        local twin = assert(LHV:Watch("Twin", { kind = "power", unit = "player", power = 0, step = 1, points = {} }))
        boot()
        live()
        local lo, hi, t = twin:Get()
        assert.are.equal(6400 / 100, hi - lo) -- one cell beside the ring
        assert.are.equal(lo .. " " .. hi, frames(1, MANA))
        local mine
        for _, h in ipairs(LHV.reg) do
            mine = (h.owner == "HekiliBelief" and h.power == 0) and h or mine
        end
        function mine.Get() -- shadows the handle's method: two cells, the L1624 shape
            return lo, hi + 6400 / 100, t, LHV.BAND
        end
        assert.are.equal(lo .. " " .. hi + 6400 / 100, frames(1, MANA))
    end)

    it("a max change: the band in points follows the new max at once (no point bars to place again)", function()
        boot()
        live()
        W.unit.player.max[0] = 1200
        Fake.event("UNIT_MAXPOWER", "player")
        assert.are.equal(("|540 552"):rep(3):sub(2), frames(3, MANA))
    end)

    it("LHV:SetEnabled(false): one unknown per channel, reason off; back on, the bands return", function()
        boot()
        live()
        LHV:SetEnabled(false)
        assert.are.equal("0 -,-1 -,2 -|", frames(2))
        assert.is_truthy(VS.Snapshot():find("state=unavailable reason=off", 1, true))
        LHV:SetEnabled(true)
        frames(140)
        assert.are.equal("0.63 0.64", frames(1, -1))
    end)

    it("a failed self-test: no watch, no band; one retry out of combat 5 s after the first world entry", function()
        Fake.set("closed", true)
        assert.is_false(Fake.login())
        boot()
        ctl.Fire("PLAYER_ENTERING_WORLD")
        assert.are.equal("", (frames(4 * 60):gsub("|", "")))
        assert.are.same({}, LHV:GetSources()) -- the capability was unavailable: no watch made
        assert.is_false((LHV:GetSelfTest()))
        Fake.set("closed", false)
        frames(61) -- past 5 s: the retry runs
        frames(140)
        assert.is_true((LHV:GetSelfTest()))
        assert.are.equal("0.63 0.64", frames(1, -1))
    end)

    it("a power neither shown nor mana is paused; shown, it primes and returns", function()
        boot()
        live()
        assert.are.equal("", frames(1, 1)) -- rage while the client shows mana
        ctl.powerType[1], ctl.powerType[2] = 1, "RAGE"
        ctl.Fire("UNIT_DISPLAYPOWER", "player")
        local row = frames(14, 1)
        assert.is_truthy(row:match("30 31$"), row)
    end)

    it("idle: 2 s with no drain pauses every watch; the next drain resumes them", function()
        boot()
        live()
        for _ = 1, 130 do
            Fake.tick(1)
            ctl.Tick(sync()) -- the frame update, no drain
        end
        assert.is_truthy(VS.Snapshot():find("state=paused", 1, true))
        assert.are.equal("-", frames(1, -1))
        frames(11)
        assert.are.equal("0.63 0.64", frames(1, -1))
    end)

    it("allocates nothing over 1000 drains with every band live", function()
        boot(false)
        live()
        local bytes = alloc.bytes(function()
            VS.Drain(sync())
            assert(I.bandLive[-1] and I.bandLive[0] and I.bandLive[MANA])
        end, 1000)
        assert.are.equal(0, bytes)
    end)
end)
