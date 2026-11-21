-- tests/LibTimeToDie/track_spec.lua: the tracking contract on LibHiddenValues' fake client: a target losing health,
-- swaps, death, a heal, a stall, a re-prime, sharing one health watch per token, pause, release, the sink, the codes,
-- a missing LibHiddenValues, combat start, and no allocation per steady frame.
local FAKE = "src/LibTimeToDie/Testing/FakeClient.lua"
local LHV_MAJOR = "LibHiddenValues-1.0"

describe("LibTimeToDie tracking", function()
    local Fake, W, ttd, lhv

    -- Health in the 1% cell below p (p - 1 to p).
    local function to(p)
        W.unit.target.health = (p - 0.5) / 100
    end

    -- From the cell below `from` down to the cell below `last`, one percent per `sec` seconds.
    local function fall(from, last, sec)
        for p = from, last, -1 do
            to(p)
            Fake.advance(sec)
        end
    end

    local function row(token, owner)
        owner = owner or "A"
        for _, r in ipairs(ttd:GetStreams()) do
            if r.token == token and r.owner == owner then
                return r
            end
        end
    end

    local function lhvSources()
        local n = 0
        for _, r in ipairs(lhv:GetSources()) do
            if r.kind == "health" then
                n = n + 1
            end
        end
        return n
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        W.unit.target = { health = 1.0 }
        ttd = LibStub("LibTimeToDie-1.0")
        lhv = LibStub(LHV_MAJOR)
        assert.is_true(Fake.login())
    end)

    after_each(function()
        local errors = Fake.errors -- what reached the client's error handler (a sink's error, the driver's, an event's)
        Fake.restore()
        assert.are.same({}, errors)
    end)

    it("primes, reads unknown at full before the first crossing, then converges on the true time", function()
        local h = ttd:Track("A", "target")
        assert.are.equal("priming", (h:State()))
        Fake.tick(12)
        local est, _, _, state = h:Get()
        assert.is_nil(est)
        assert.are.equal("unknown", state)
        fall(99, 60, 0.5) -- 0.5 s per percent: about 30 s left in the cell below 60
        local lo, hi, reason
        est, lo, hi, state, reason = h:Get()
        assert.are.equal("live", state)
        assert.are.equal("fit", reason)
        assert.is_true(math.abs(est - 29.5) < 3, tostring(est))
        assert.is_true(lo <= est and est <= hi)
        assert.are.same({ "live", "fit" }, { h:State() })
    end)

    it("a target change starts a fresh stream that answers from the carried rate", function()
        local h = ttd:Track("A", "target")
        Fake.tick(12)
        fall(99, 80, 0.5)
        assert.are.equal(20, row("target").crossings) -- kept for the fit: at most the ring's 32
        W.unit.target = { health = 0.495 }
        Fake.event("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, row("target").crossings)
        assert.are.equal("priming", select(4, h:Get()))
        Fake.tick(12)
        local est, _, _, state, reason = h:Get()
        assert.are.equal("live", state)
        assert.are.equal("prior", reason) -- no crossing yet: the last mob's rate from the band's middle
        assert.is_true(math.abs(est - 49.5 * 0.5) < 2, tostring(est))
    end)

    it("a re-prime of the same unit keeps the history and keeps answering", function()
        local h = ttd:Track("A", "target")
        Fake.tick(12)
        fall(99, 80, 0.5)
        Fake.event("UI_SCALE_CHANGED") -- LibHiddenValues primes the source again
        Fake.tick(2)
        assert.are.equal("priming", (lhv.sources[1].handles[1]:State()))
        local est, _, _, state = h:Get()
        assert.are.equal("live", state)
        assert.is_number(est)
        Fake.tick(12)
        fall(79, 70, 0.5)
        assert.are.equal(30, row("target").crossings) -- 20 before the re-prime, 10 after
        est = h:Get()
        assert.is_true(math.abs(est - 34.5) < 3, tostring(est))
    end)

    it("death clears the stream and keeps the handle; a new target brings it back", function()
        local h = ttd:Track("A", "target")
        Fake.tick(12)
        fall(99, 80, 0.5)
        W.unit.target.health = 0
        W.unit.target.dead = true
        Fake.event("UNIT_HEALTH", "target")
        Fake.tick(2)
        assert.are.same({ "gone" }, { h:State() })
        assert.is_nil((h:Get()))
        assert.are.equal(0, row("target").crossings)
        W.unit.target = nil -- no target at all: still gone
        Fake.event("PLAYER_TARGET_CHANGED")
        Fake.tick(2)
        assert.are.equal("gone", (h:State()))
        W.unit.target = { health = 0.795 }
        Fake.event("PLAYER_TARGET_CHANGED")
        Fake.tick(12)
        assert.are.equal("live", (h:State())) -- the carried rate answers at once
    end)

    it("a death the client keeps secret is not gone: the band reaches 0-1 and the estimate stays near 0", function()
        local h = ttd:Track("A", "target")
        Fake.tick(12)
        fall(99, 80, 0.5)
        W.secretBool = true -- UnitIsDead returns a secret, as it may under the dungeon restrictions
        W.unit.target.health = 0
        W.unit.target.dead = true
        Fake.event("UNIT_HEALTH", "target")
        Fake.advance(2)
        local est, _, _, state = h:Get()
        assert.are.equal("live", state)
        assert.is_true(est < 1, tostring(est))
        W.unit.target = nil
        Fake.event("PLAYER_TARGET_CHANGED")
        Fake.tick(2)
        assert.are.equal("gone", (h:State())) -- the target cleared: gone
    end)

    it("a heal restarts the fit and keeps answering; a stall holds the countdown", function()
        local h = ttd:Track("A", "target")
        Fake.tick(12)
        fall(99, 70, 0.5)
        to(75) -- healed by 5%
        Fake.tick(3)
        local est, _, _, state, reason = h:Get()
        assert.are.equal("live", state)
        assert.are.equal("prior", reason)
        assert.is_true(math.abs(est - 74.5 * 0.5) < 4, tostring(est))
        fall(74, 60, 0.5)
        Fake.advance(5) -- no crossing for 5 s: a stall
        local at5 = h:Get()
        Fake.advance(5)
        est, _, _, state, reason = h:Get()
        assert.are.equal("live", state)
        assert.are.equal("stalled", reason)
        -- held: without the hold it would be 5 s lower; the deadband lets it run down a little between republishes
        assert.is_true(math.abs(est - at5) < 2.5, est .. " vs " .. at5)
    end)

    it("several tracks of one token share one health watch; pause and release count them", function()
        local a = ttd:Track("A", "target")
        local b = ttd:Track("B", "target")
        local p = ttd:Track("A", "player")
        local a2 = ttd:Track("A", "target") -- a second track of A on the target shares A's estimate
        Fake.tick(12)
        assert.are.equal(2, lhvSources()) -- target and player
        assert.are.equal(2, row("target").tracks)
        assert.are.equal(1, row("target", "B").tracks)
        a2:Release()
        for _, r in ipairs(lhv:GetSources()) do
            assert.are.equal(1, r.handles) -- one watch per token
        end
        a:SetPaused(true)
        Fake.tick(1)
        assert.are.equal("paused", (a:State()))
        assert.is_true(lhv.sources[1].active) -- b still wants it
        b:SetPaused(true)
        Fake.tick(1)
        assert.is_false(lhv.sources[1].active) -- the watch is paused too
        assert.are.equal("paused", select(4, b:Get()))
        b:SetPaused(false)
        Fake.tick(12)
        assert.is_true(lhv.sources[1].active)
        assert.are.equal("unknown", (b:State())) -- full, no crossing yet
        a:Release()
        assert.are.equal("released", (a:State()))
        assert.are.equal("released", select(4, a:Get()))
        a:Release() -- twice is harmless
        assert.are.equal(2, lhvSources())
        b:Release()
        assert.are.equal(1, lhvSources()) -- the last track freed the watch
        assert.is_nil(row("target", "B"))
        p:Release()
        assert.are.equal(0, lhvSources())
        assert.is_nil(next(ttd.byLhv)) -- no released watch is kept
        Fake.tick(1)
        assert.is_nil(ttd.frame:GetScript("OnUpdate")) -- the driver stops with the last stream
        ttd:Track("A", "target")
        assert.is_not_nil(ttd.frame:GetScript("OnUpdate")) -- and starts with the next
    end)

    it("releasing the only unpaused track of a shared token pauses the watch", function()
        local a = ttd:Track("A", "target")
        local b = ttd:Track("B", "target")
        Fake.tick(12)
        a:SetPaused(true)
        Fake.tick(1)
        assert.is_true(lhv.sources[1].active)
        b:Release()
        Fake.tick(1)
        assert.is_false(lhv.sources[1].active)
    end)

    it("an owner tracking a unit already watched starts from the current band", function()
        local a = ttd:Track("A", "target")
        Fake.tick(12)
        fall(99, 80, 0.5)
        local b = ttd:Track("B", "target")
        assert.are.equal("unknown", (b:State())) -- not priming: the watch has the band
        fall(79, 77, 0.5)
        assert.are.equal(3, row("target", "B").crossings) -- the first crossing counts
        assert.are.equal(23, row("target").crossings)
        assert.are.equal("live", (a:State()))
    end)

    it("an owner joining a paused watch does not start from the band it held before the pause", function()
        local a = ttd:Track("A", "target")
        Fake.tick(12)
        fall(99, 80, 0.5)
        a:SetPaused(true)
        Fake.tick(1)
        fall(79, 60, 0.5) -- unseen: the watch is paused
        ttd:Track("B", "target") -- the watch resumes and primes the current band
        Fake.tick(12)
        assert.are.equal(0, row("target", "B").crossings) -- no 20% "crossing" from the stale band
    end)

    it("a stream LibHiddenValues reports unavailable does not keep the driver running", function()
        local h = ttd:Track("A", "focus")
        Fake.tick(3)
        assert.are.same({ "unavailable", "unproven" }, { h:State() })
        Fake.tick(1)
        assert.is_nil(ttd.frame:GetScript("OnUpdate"))
        lhv:SetEnabled(false) -- a capability change wakes it for a fresh look
        assert.is_not_nil(ttd.frame:GetScript("OnUpdate"))
        Fake.tick(2)
        assert.are.equal("unavailable", (h:State())) -- read again; LibHiddenValues names the unproven unit first
        assert.is_nil(ttd.frame:GetScript("OnUpdate"))
    end)

    it("a stream that started without LibHiddenValues and then was refused tries again", function()
        local saved = LibStub.libs[LHV_MAJOR]
        rawset(LibStub.libs, LHV_MAJOR, nil)
        local h = ttd:Track("A", "target")
        assert.are.same({ "unavailable", "lhv-missing" }, { h:State() })
        rawset(LibStub.libs, LHV_MAJOR, saved)
        local watch = lhv.Watch
        lhv.Watch = function()
            return nil, "pool-limit"
        end
        Fake.advance(1.1) -- the next try: lib.RETRY (1 s) after the last
        assert.are.same({ "unavailable", "pool-limit" }, { h:State() })
        lhv.Watch = watch
        Fake.advance(1.1) -- the next try: lib.RETRY (1 s) after the last
        local state = h:State()
        assert.is_true(state == "priming" or state == "unknown", state) -- attached (the driver may have primed it)
    end)

    it("a refused stream read every frame retries once a second and allocates nothing per frame", function()
        local saved = LibStub.libs[LHV_MAJOR]
        rawset(LibStub.libs, LHV_MAJOR, nil)
        local h = ttd:Track("A", "target")
        rawset(LibStub.libs, LHV_MAJOR, saved)
        local calls = 0
        lhv.Watch = function()
            calls = calls + 1
            local handle = {} -- as LibHiddenValues does: the handle is built before the refusal
            return handle and nil, "pool-limit"
        end
        for _ = 1, 120 do
            Fake.tick(1)
            h:Get()
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        calls = 0
        for _ = 1, 300 do -- 5 s
            Fake.tick(1)
            h:Get()
        end
        local grew = collectgarbage("count") - before
        collectgarbage("restart")
        assert.are.equal("pool-limit", select(5, h:Get()))
        assert.is_true(calls >= 4 and calls <= 6, tostring(calls))
        assert.is_true(grew < 1, grew .. " KB")
    end)

    it("an older LibHiddenValues than the one required reads unavailable, lhv-old", function()
        local minor = LibStub.minors[LHV_MAJOR]
        rawset(LibStub.minors, LHV_MAJOR, ttd.LHV_MIN - 1)
        local h = ttd:Track("A", "target")
        assert.are.same({ "unavailable", "lhv-old" }, { h:State() })
        assert.are.same({ false, "unavailable", "lhv-old" }, { ttd:IsAvailable("target") })
        assert.is_string(ttd:GetMessage("lhv-old"))
        rawset(LibStub.minors, LHV_MAJOR, minor)
        Fake.advance(1.1) -- the next try: lib.RETRY (1 s) after the last
        assert.are.equal("priming", (h:State()))
    end)

    it("ReleaseAll drops one owner's tracks only", function()
        local a = ttd:Track("A", "target")
        local b = ttd:Track("B", "target")
        ttd:ReleaseAll("A")
        assert.are.equal("released", (a:State()))
        assert.are_not.equal("released", (b:State()))
        assert.is_nil(row("target"))
        assert.are.equal(1, row("target", "B").tracks)
    end)

    it("calls the sink only when the published estimate or the state changes, at most once per frame", function()
        local calls = {}
        local h = ttd:Track("A", "target", function(hh, est, lo, hi, state)
            calls[#calls + 1] = { h = hh, t = GetTime(), est = est, lo = lo, hi = hi, state = state }
        end)
        Fake.tick(12)
        assert.are.equal("priming", calls[1].state)
        assert.are.equal("unknown", calls[#calls].state)
        local before = #calls
        fall(99, 60, 0.5) -- 20 s, 1200 frames
        local n = #calls - before
        assert.is_true(n >= 1 and n < 40, tostring(n))
        local last = calls[#calls]
        assert.are.equal("live", last.state)
        assert.is_true(last.lo <= last.est and last.est <= last.hi)
        h:SetPaused(true)
        Fake.tick(1)
        assert.are.equal("paused", calls[#calls].state)
        assert.is_nil(calls[#calls].est)
        local m = #calls
        Fake.tick(30)
        assert.are.equal(m, #calls) -- nothing changed: no call
        h:SetSink(nil)
        h:SetPaused(false)
        Fake.tick(30)
        assert.are.equal(m, #calls)
        for i = 1, #calls do -- the sink runs under pcall: its own asserts would not fail the test
            assert.are.equal(h, calls[i].h)
            assert.is_true(i == 1 or calls[i].t > calls[i - 1].t, "two calls in one frame")
        end
    end)

    it("refuses bad input with codes, and every code, state and reason has a message", function()
        local E = ttd.ERR
        assert.are.same({ nil, E.OWNER_INVALID }, { ttd:Track(1, "target") })
        assert.are.same({ nil, E.UNIT_INVALID }, { ttd:Track("A", 5) })
        assert.are.same({ nil, E.UNIT_INVALID }, { ttd:Track("A", "target-1") })
        assert.are.same({ nil, E.SINK_INVALID }, { ttd:Track("A", "target", 5) })
        for _, code in pairs(E) do
            assert.is_string(ttd:GetMessage(code), code)
        end
        local words = { "live", "priming", "gone", "unknown", "unavailable", "paused", "released" }
        for _, w in ipairs({ "lhv-missing", "lhv-old", "fit", "seed", "prior", "stalled", "pending", "suspended" }) do
            words[#words + 1] = w
        end
        for _, w in ipairs(words) do
            assert.is_string(ttd:GetMessage(w), w)
        end
        assert.are.equal(lhv:GetMessage("unproven"), ttd:GetMessage("unproven")) -- LibHiddenValues' reasons
        assert.is_nil(ttd:GetMessage("live", "deDE"))
        assert.are.same({ "LibTimeToDie-1.0", 2 }, { ttd:GetVersion() })
    end)

    it("a token LibHiddenValues has not proven reads unavailable with its reason", function()
        local h = ttd:Track("A", "focus")
        Fake.tick(2)
        assert.are.same({ "unavailable", "unproven" }, { h:State() })
        assert.are.same({ false, "unavailable", "unproven" }, { ttd:IsAvailable("focus") })
        assert.are.same({ true, "ready" }, { ttd:IsAvailable("target") })
    end)

    it("without LibHiddenValues a handle reads unavailable and attaches once it is there", function()
        local saved = LibStub.libs[LHV_MAJOR]
        rawset(LibStub.libs, LHV_MAJOR, nil)
        local h = ttd:Track("A", "target")
        assert.are.same({ "unavailable", "lhv-missing" }, { h:State() })
        assert.are.same({ false, "unavailable", "lhv-missing" }, { ttd:IsAvailable("target") })
        rawset(LibStub.libs, LHV_MAJOR, saved)
        Fake.advance(1.1) -- the next try (lib.RETRY after the last) attaches
        assert.are.equal("priming", (h:State()))
        Fake.tick(12)
        assert.are.equal("unknown", (h:State()))
    end)

    it("combat start anchors a mob that was targeted at full long before the pull", function()
        local h = ttd:Track("A", "target")
        Fake.tick(12)
        Fake.advance(20) -- targeted, nobody hits it
        Fake.event("PLAYER_REGEN_DISABLED")
        Fake.advance(0.5) -- the first percent falls half a second into the pull
        fall(99, 96, 0.5) -- four crossings: the fit is clamped to 0.2-5x the slope since the anchor
        local est = h:Get()
        assert.is_true(math.abs(est - 95.5 * 0.5) < 0.15 * 95.5 * 0.5, tostring(est))
    end)

    it("allocates nothing per steady frame, two owners on one target, with a sink and a Get every frame", function()
        local n = 0
        local h = ttd:Track("A", "target", function()
            n = n + 1
        end)
        ttd:Track("B", "target", function()
            n = n + 1
        end)
        ttd:HintBelow("B", 20)
        Fake.tick(12)
        local p = 99
        local function frame(i)
            if i % 30 == 0 then
                p = p > 2 and p - 1 or 99
                to(p)
            end
            Fake.tick(1)
            h:Get()
        end
        for i = 1, 600 do
            frame(i)
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for i = 1, 1200 do
            frame(i)
        end
        local grew = collectgarbage("count") - before
        collectgarbage("restart")
        assert.is_true(n > 0)
        assert.is_true(grew < 0.5, grew .. " KB")
    end)
end)
