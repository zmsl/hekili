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

    -- (integration design 3.4, lane B7) the compiler leaves out a resource whose priority compares it with more exact
    -- values than the library takes per source: the two caps are one number
    it("Hekili's APL point cap is the library's points per source", function()
        local ns = {}
        assert(loadfile("src/Hekili/Engine/Sim/AplThresholds.lua"))("Hekili", ns)
        local LHV = api.LibStub(MAJOR)
        assert.are.equal(LHV.POINTS_PER_SOURCE, ns.APL_POINT_CAP)
        assert.are.equal(LHV.POINTS_PER_SOURCE, select(5, LHV:GetPool()))
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
