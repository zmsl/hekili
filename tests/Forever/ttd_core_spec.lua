-- tests/Forever/ttd_core_spec.lua (lane B8, owner L1676): the core's time to die from LibTimeToDie, called directly
-- (owner "Hekili", the target by token), inside Engine/Sim/Targets.lua's existing functions; every caller unchanged.
-- A live estimate answers GetTTD, GetTimeToPct and fight_remains (GetGreatestTTD); every other state answers today's
-- unknown, 3600. Tracked on the first query, released by Hekili.bandOff (the bands' hidden switch) and at disable.
-- The library here is a double in the instance's LibStub (its own specs pin the real one).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local MAJOR = "LibTimeToDie-1.0"

-- A LibTimeToDie double: one handle, its answer set by the test; counts Track and Release, records hints.
local function double()
    local lib = { tracks = 0, released = 0, hints = {} }
    local h = { state = "priming" }
    function h:Get()
        return self.est, self.lo, self.hi, self.state, self.reason
    end
    function h:Release()
        lib.released = lib.released + 1
    end
    function lib:Track(owner, token)
        lib.tracks, lib.owner, lib.token = lib.tracks + 1, owner, token
        return h
    end
    function lib:HintBelow(owner, pct, factor)
        lib.hints[#lib.hints + 1] = { "below", owner, pct, factor }
        return true
    end
    lib.h = h
    return lib
end

local function install(H, lib)
    local stub = rawget(H.env, "LibStub")
    stub.libs[MAJOR], stub.minors[MAJOR] = lib, 2
end

describe("time to die from LibTimeToDie (lane B8)", function()
    local H, hk, lib

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        hk = H.Hekili
        H.ctl.exists.target = true
        lib = double()
    end)

    it("without the library every answer is today's unknown, 3600", function()
        assert.are.equal(3600, hk:GetTTD("target"))
        assert.are.equal(3600, hk:GetGreatestTTD())
        assert.are.equal(3600, hk:GetLowestTTD())
        assert.are.equal(3600, hk:GetTimeToPct("target", 35))
    end)

    it("tracks the target lazily, once, as owner Hekili", function()
        install(H, lib)
        assert.are.equal(0, lib.tracks)
        hk:GetTTD("target")
        hk:GetTTD("target")
        hk:GetGreatestTTD()
        assert.are.same({ 1, "Hekili", "target" }, { lib.tracks, lib.owner, lib.token })
    end)

    it("a live estimate answers GetTTD, GetGreatestTTD, GetLowestTTD and fight_remains", function()
        install(H, lib)
        lib.h.state, lib.h.est, lib.h.lo, lib.h.hi, lib.h.reason = "live", 12.5, 8, 20, "fit"
        assert.are.equal(12.5, hk:GetTTD("target"))
        assert.are.equal(12.5, hk:GetGreatestTTD())
        assert.are.equal(12.5, hk:GetLowestTTD())
        local st = hk.State
        st.reset()
        assert.are.equal(12.5, st.fight_remains)
        assert.are.equal(12.5, st.target.time_to_die)
    end)

    it("priming, unknown, gone, unavailable and paused answer 3600", function()
        install(H, lib)
        lib.h.est = 9
        for _, s in ipairs({ "priming", "unknown", "gone", "unavailable", "paused" }) do
            lib.h.state = s
            assert.are.equal(3600, hk:GetTTD("target"), s)
            assert.are.equal(3600, hk:GetGreatestTTD(), s)
            assert.are.equal(3600, hk:GetTimeToPct("target", 35), s)
        end
    end)

    it("a friendly target answers 3600 (the existing hostility test)", function()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 9
        H.ctl.friendly.target = true
        assert.are.equal(3600, hk:GetTTD("target"))
        assert.are.equal(3600, hk:GetTimeToPct("target", 35))
    end)

    it("time to a percent: est x (h - p) / h, h the facade's target health; 0 at or below it", function()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 20
        -- the belief's target health with no band: full (100)
        assert.are.equal(13, hk:GetTimeToPct("target", 35))
        assert.are.equal(13, hk:GetTimeToPct("target", 0.35))
        assert.are.equal(0, hk:GetTimeToPct("target", 100))
    end)

    it("Hekili.bandOff releases the track and answers 3600; off again tracks anew", function()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 9
        assert.are.equal(9, hk:GetTTD("target"))
        hk.bandOff = true
        assert.are.equal(3600, hk:GetTTD("target"))
        assert.are.equal(3600, hk:GetGreatestTTD())
        assert.are.same({ 1, 1 }, { lib.tracks, lib.released })
        hk.bandOff = nil
        assert.are.equal(9, hk:GetTTD("target"))
        assert.are.same({ 2, 1 }, { lib.tracks, lib.released })
    end)

    it("disable releases the track", function()
        install(H, lib)
        hk:GetTTD("target")
        hk:OnDisable()
        assert.are.equal(1, lib.released)
    end)

    it("the snapshot's time to die line: state, reason, est/lo/hi (English only)", function()
        install(H, lib)
        assert.is_truthy(hk:GetTTDInfo():match("time to die: not tracked"))
        lib.h.state, lib.h.est, lib.h.lo, lib.h.hi, lib.h.reason = "live", 12.5, 8, 20, "fit"
        hk:GetTTD("target")
        local s = hk:GetTTDInfo()
        assert.is_truthy(s:match("live fit est 12%.5 lo 8%.0 hi 20%.0"), s)
    end)

    it("reads allocate nothing", function()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 9
        hk:GetTTD("target")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            hk:GetTTD("target")
            hk:GetGreatestTTD()
            hk:GetTimeToPct("target", 35)
        end
        local after = collectgarbage("count")
        collectgarbage("restart")
        assert.are.equal(before, after)
    end)
end)
