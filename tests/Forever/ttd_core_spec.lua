-- tests/Forever/ttd_core_spec.lua (lane B8, owner L1676): the core's time to die from LibTimeToDie, called directly
-- (owner "Hekili", the target by token), inside Engine/Sim/Targets.lua's existing functions; every caller unchanged.
-- A live estimate answers GetTTD, GetTimeToPct and fight_remains (GetGreatestTTD); every other state answers today's
-- unknown, 3600, priming too (nothing is kept through it). Tracked on the first query, released by Hekili.bandOff (the
-- bands' hidden switch) and at disable.
-- The library here is a double in the instance's LibStub (its own specs pin the real one).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

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
        if lib.refuse then
            return nil, "pool-limit"
        end
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

    -- L1703: the GUID tracker was never fed (removed); its getters keep the answers its empty table gave.
    it("the getters only the GUID tracker could answer keep their empty-tracker answers", function()
        H.ctl.exists.focus = true
        assert.are.same({ 3600, 3600 }, { hk:GetTTD("focus"), hk:GetTimeToPct("focus", 35) })
        assert.are.same({ 3600, 3600 }, { hk:GetDeathClockByGUID("Creature-0-1-2-3-4-5"), hk:GetGreatestTimeToPct(35) })
        assert.are.equal(0.35 * 3600, hk:GetTimeToPctByGUID("Creature-0-1-2-3-4-5", 35))
        assert.are.equal(0.2 * 3600, hk:GetTimeToPctByGUID(nil, 0.2))
        assert.are.same({ 0, 0 }, { hk:GetNumTTDsWithin(10), hk:GetNumTTDsBefore(10) })
        assert.are.equal(hk.State.active_enemies, hk:GetNumTTDsAfter(10))
        assert.are.same({ 0, 0 }, { hk:GetNumTargetsAboveHealthPct(20), hk:GetNumTargetsBelowHealthPct(20, true) })
        assert.are.equal(3600, hk:GetAddWaveTTD())
        assert.is_truthy(hk:GetTTDInfo():match("\ntargets:  none$"))
        H.ctl.exists.boss1 = true
        assert.are.equal(0, hk:GetAddWaveTTD()) -- a boss up: the empty table's 0
        hk:ExpireTTDs()
        rawset(hk.State.target, "is_dummy", true)
        assert.are.same({ 180, 180, 180, 180 }, {
            hk:GetTTD("focus"),
            hk:GetDeathClockByGUID("x"),
            hk:GetGreatestTTD(),
            hk:GetAddWaveTTD(),
        })
        assert.are.equal(3600, hk:GetTimeToPct("focus", 35))
        assert.are.equal(0, hk:GetNumTTDsWithin(10))
        assert.is_truthy(
            hk:GetTTDInfo():match("\ntargets:    Target TTDs overridden; target is a training dummy  none$")
        )
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

    -- The future state (State.lua): target.time_to_die is real_ttd less offset + delay, floored at 1, real_ttd read once
    -- per reset (3600, unknown, is kept as it is); fight_remains, interpolated_fight_remains and the state-level
    -- time_to_die are longest_ttd less offset + delay, floored at 1, with no unknown case: an unknown 3600 counts down.
    it(
        "in the future state: the estimate less offset + delay, floored at 1; an unknown target time stays 3600",
        function()
            install(H, lib)
            lib.h.state, lib.h.est, lib.h.lo, lib.h.hi, lib.h.reason = "live", 20, 15, 25, "fit"
            local st = hk.State
            local function reads()
                return { st.target.time_to_die, st.fight_remains, st.interpolated_fight_remains, st.time_to_die }
            end
            st.reset()
            assert.are.same({ 0, 0 }, { st.offset, st.delay })
            assert.are.same({ 20, 20, 20, 20 }, reads())
            st.advance(3)
            st.delay = 0.5
            assert.are.same({ 3, 0.5 }, { st.offset, st.delay })
            assert.are.same({ 16.5, 16.5, 16.5, 16.5 }, reads())
            lib.h.est = 99 -- read once per reset: a new answer waits for the next
            assert.are.same({ 16.5, 16.5, 16.5, 16.5 }, reads())
            st.advance(30)
            assert.are.same({ 1, 1, 1, 1 }, reads())

            lib.h.state = "unknown"
            st.reset()
            assert.are.same({ 3600, 3600, 3600, 3600 }, reads())
            st.advance(3)
            st.delay = 0.5
            -- reported (vendor-libs-next), not changed: fight_remains and the state-level time_to_die count an unknown down
            assert.are.same({ 3600, 3596.5, 3596.5, 3596.5 }, reads())
            st.advance(30)
            assert.are.same({ 3600, 3567, 3567, 3567 }, reads())
        end
    )

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

    -- vendor-libs: B8's 0.5 s keep is gone. LibTimeToDie answers priming only with no estimate, after a target change
    -- (a re-prime of the same unit keeps answering), and minor 4 then answers nothing before 1.5 s of the new target's
    -- loss: the keep bridged to no answer and showed the last target's time on this one.
    it("priming after a live answer: fight_remains reads 3600 too, the last answer is not kept", function()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 12
        assert.are.equal(12, hk:GetGreatestTTD())
        lib.h.state = "priming"
        H.ctl.now = H.ctl.now + 0.1
        assert.are.same({ 3600, 3600 }, { hk:GetGreatestTTD(), hk:GetLowestTTD() })
        local st = hk.State
        st.reset()
        assert.are.same({ 3600, 3600 }, { st.fight_remains, st.target.time_to_die })
    end)

    it("a secret answer to the hostility test is never truth-tested: 3600", function()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 9
        H.ctl.exists.target = fake.SECRET
        assert.are.equal(3600, hk:GetTTD("target"))
        H.ctl.exists.target, H.ctl.friendly.target = true, fake.SECRET
        assert.are.equal(3600, hk:GetTTD("target"))
    end)

    it("a refused track is asked again at most once a second", function()
        install(H, lib)
        lib.refuse = true
        for _ = 1, 1000 do
            assert.are.equal(3600, hk:GetTTD("target"))
        end
        assert.are.equal(1, lib.tracks)
        H.ctl.now = H.ctl.now + 0.75
        hk:GetGreatestTTD()
        assert.are.equal(1, lib.tracks)
        H.ctl.now = H.ctl.now + 0.25
        lib.refuse, lib.h.state, lib.h.est = nil, "live", 9
        assert.are.equal(9, hk:GetTTD("target"))
        assert.are.equal(2, lib.tracks)
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

    it("time to a percent below full health: scaled by the target health's band, 0 at 0 percent", function()
        H.ctl.guid.target = "Creature-1"
        assert.is_true(headless.cycle(H, H.ctl.now + 1))
        local I, Obs, t = H.ns.VirtualStateInternal, H.ns.VirtualState.Obs, H.ctl.now
        install(H, lib)
        lib.h.state, lib.h.est = "live", 20
        local function band(lo, hi)
            I.Sources.Direct(Obs.Band, t, -1, lo, hi)
            I.Fold(t)
        end
        band(0.30, 0.31) -- reads 30.5
        assert.is_true(math.abs(hk:GetTimeToPct("target", 20) - 20 * 10.5 / 30.5) < 1e-9) -- not 16, full health's
        assert.are.equal(0, hk:GetTimeToPct("target", 35))
        I.Sources.Direct(Obs.TargetGone, t, 1)
        I.Fold(t)
        assert.are.equal(0, hk:GetTimeToPct("target", 0)) -- health 0 and 0 percent: never 0 / 0
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
        assert.is_truthy(s:match("live fit est 12%.5 lo 8 hi 20;"), s)
    end)

    -- L1736, owner's A (L1742), kept by vendor-libs on its fight runs: a live seed reads unknown everywhere.
    it("a live seed answers 3600 everywhere; every other live reason answers; the line says the reason", function()
        install(H, lib)
        lib.h.state, lib.h.est, lib.h.lo, lib.h.hi, lib.h.reason = "live", 3.5, 1.75, 10.5, "seed"
        assert.are.same(
            { 3600, 3600, 3600 },
            { hk:GetTTD("target"), hk:GetGreatestTTD(), hk:GetTimeToPct("target", 35) }
        )
        assert.is_truthy(hk:GetTTDInfo():match("time to die: live seed est 3%.5 lo 1%.75 hi 10%.5;"))
        for _, why in ipairs({ "prior", "fit", "stalled" }) do
            lib.h.state, lib.h.est, lib.h.lo, lib.h.hi, lib.h.reason = "live", 20, 10, 40, why
            assert.are.same(
                { 20, 20, 13 },
                { hk:GetTTD("target"), hk:GetGreatestTTD(), hk:GetTimeToPct("target", 35) },
                why
            )
            assert.is_truthy(hk:GetTTDInfo():match("time to die: live " .. why .. " est 20 lo 10 hi 40;"), why)
        end
    end)

    it("a debug snapshot carries the line", function()
        install(H, lib)
        lib.h.state, lib.h.est, lib.h.lo, lib.h.hi, lib.h.reason = "live", 12.5, 8, 20, "fit"
        hk:GetTTD("target")
        hk.GenerateProfile = function() -- it trips on a harness talent stub (output_spec)
            return "profile"
        end
        H.env.Screenshot = function() end
        hk.Engine.Snapshot()
        local snap = H.ns.snapshots[#H.ns.snapshots]
        assert.is_truthy(snap, "no snapshot stored")
        assert.is_truthy(snap.log:find("time to die: live fit est 12.5", 1, true))
    end)

    it("reads allocate nothing, live, through priming or refused", function()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 9
        hk:GetTTD("target")
        hk:GetGreatestTTD()
        local function reads()
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
        end
        reads()
        lib.h.state = "priming"
        reads()
        hk.bandOff = true
        hk:GetTTD("target")
        hk.bandOff, lib.refuse = nil, true
        hk:GetTTD("target")
        reads()
    end)
end)

-- Upstream's meaning (owner decision 2026-11-22): fight_remains and longest_ttd are the LONGEST time to die among the
-- enemies. Only the target is tracked, so with more than one enemy the longest (and the shortest) is unknown; the
-- target's own time_to_die is its estimate at any count. The count is the real one, from plates (caster_range_spec's).
describe("time to die with more than one enemy (lane B8)", function()
    -- `secret`: the units' GUIDs are secret (the Map restriction), so plates are counted by token
    local function boot(secret)
        local new = fake.new
        fake.new = function(...) -- both plate CVars on, before the facade resolves GetCVar
            local api, ctl = new(...)
            api.GetCVar = function()
                return "1"
            end
            return api, ctl
        end
        local ok, H = pcall(headless.new, { character = ww.character(), pack = ww.PACK })
        fake.new = new
        assert(ok, H)
        assert.are.same({}, H.loadErrors)
        local ctl = H.ctl
        ctl.exists.target, ctl.inRange.target, ctl.level.target = true, true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, ctl.now + 0.2))
        if secret then
            ctl.guid.target = fake.SECRET
            ctl.unitIs.target = "nameplate1" -- a token plate is compared as ("target", plate)
        end
        ctl.guid.nameplate1, ctl.exists.nameplate1, ctl.unitIs.nameplate1 = ctl.guid.target, true, "target"
        ctl.distance.nameplate1, ctl.unitCombat.nameplate1 = 3, true
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        local lib = double()
        install(H, lib)
        lib.h.state, lib.h.est = "live", 5
        return H
    end

    local function count(H, n)
        for i = 2, n do
            local unit = "nameplate" .. i
            H.ctl.guid[unit] = H.ctl.guid.target == fake.SECRET and fake.SECRET or "Creature-p" .. i
            H.ctl.exists[unit] = true
            H.ctl.distance[unit], H.ctl.unitCombat[unit] = 3, true
            H.Fire("NAME_PLATE_UNIT_ADDED", unit)
        end
        for i = math.max(2, n + 1), 3 do
            local unit = "nameplate" .. i
            if H.ctl.exists[unit] then
                H.Fire("NAME_PLATE_UNIT_REMOVED", unit)
                H.ctl.exists[unit] = false
            end
        end
        H.ctl.now = H.ctl.now + 0.2 -- past LibRangeCheck's cache
        return H.ns.getNumberTargets(true)
    end

    it("one enemy: fight_remains is the target's estimate", function()
        local H = boot()
        assert.are.equal(1, count(H, 1))
        local st = H.Hekili.State
        st.reset()
        assert.are.same({ 5, 5, 5 }, { st.fight_remains, st.longest_ttd, st.target.time_to_die })
    end)

    it("three enemies, the target dying in 5 s: fight_remains 3600, target.time_to_die 5", function()
        local H = boot()
        assert.are.equal(3, count(H, 3))
        assert.are.equal(3, count(H, 3)) -- held one update
        local st, hk = H.Hekili.State, H.Hekili
        st.reset()
        assert.are.same({ 3, 3600, 5 }, { st.active_enemies, st.fight_remains, st.target.time_to_die })
        assert.are.same({ 3600, 3600, 5 }, { hk:GetGreatestTTD(), hk:GetLowestTTD(), hk:GetTTD("target") })
    end)

    it("exactly two enemies: fight_remains 3600", function()
        local H = boot()
        count(H, 2)
        assert.are.equal(2, count(H, 2))
        assert.are.same({ 3600, 3600 }, { H.Hekili:GetGreatestTTD(), H.Hekili:GetLowestTTD() })
    end)

    it("a change of one or several is followed after it held one update; the count itself is not held", function()
        local H = boot()
        local counts, greatest = {}, {}
        for i, n in ipairs({ 1, 2, 1, 1, 2, 2, 3, 1, 2, 1, 1 }) do
            counts[i], greatest[i] = count(H, n), H.Hekili:GetGreatestTTD()
            assert.are.equal(5, H.Hekili:GetTTD("target"))
        end
        assert.are.same({ 1, 2, 1, 1, 2, 2, 3, 1, 2, 1, 1 }, counts)
        assert.are.same({ 5, 5, 5, 5, 5, 3600, 3600, 3600, 3600, 3600, 5 }, greatest)
    end)

    it("secret plates: a fall the count already held one update waits no second one", function()
        local H = boot(true)
        count(H, 2)
        assert.are.equal(2, count(H, 2))
        assert.are.equal(3600, H.Hekili:GetGreatestTTD())
        assert.are.same({ 2, 3600 }, { count(H, 1), H.Hekili:GetGreatestTTD() })
        assert.are.same({ 1, 5 }, { count(H, 1), H.Hekili:GetGreatestTTD() })
    end)

    it("the target's time read while several is not what priming keeps for one", function()
        local H = boot()
        count(H, 2)
        count(H, 2)
        assert.are.same({ 5, 3600 }, { H.Hekili:GetTTD("target"), H.Hekili:GetGreatestTTD() })
        count(H, 1)
        count(H, 1)
        rawget(H.env, "LibStub").libs[MAJOR].h.state = "priming"
        assert.are.equal(3600, H.Hekili:GetGreatestTTD())
    end)
end)
