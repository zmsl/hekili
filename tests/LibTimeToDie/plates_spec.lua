-- tests/LibTimeToDie/plates_spec.lua: minor 5's lives on LibHiddenValues' fake client. A mob's estimate (a life, with
-- an id) moves to its nameplate when you switch away and back when you return; the plate feeds it at 5%. The hand-off,
-- the take-back, the continuity veto, the feed rules, the release rules, the opt-out, explicit plate tracks, the new
-- calls (Get by token, Recent, SetRecent), the upgrade from minor 4 and the costs (none for a boss you never leave).
local FAKE = "src/LibTimeToDie/Testing/FakeClient.lua"
local LHV_MAJOR = "LibHiddenValues-1.0"

describe("LibTimeToDie lives", function()
    local Fake, W, ttd, lhv, boss, add

    local function row(token, owner)
        for _, r in ipairs(ttd:GetStreams()) do
            if r.token == token and r.owner == (owner or "A") then
                return r
            end
        end
    end

    local function source(unit)
        for _, r in ipairs(lhv:GetSources()) do
            if r.kind == "health" and r.unit == unit then
                return r
            end
        end
    end

    local function nSources()
        return #lhv:GetSources()
    end

    local function id(h)
        return (select(6, h:Get()))
    end

    local function swap(u)
        W.unit.target = u
        Fake.event("PLAYER_TARGET_CHANGED")
    end

    -- boss and add lose b and a percent a second, frame by frame
    local function burn(sec, b, a)
        for _ = 1, math.floor(sec * 60 + 0.5) do
            boss.health = boss.health - b / 6000
            add.health = add.health - (a or 0) / 6000
            Fake.tick(1)
        end
    end

    -- A tracked boss in combat, 2% a second from full to the 71-72 cell (a crossing at 72 is its last).
    local function engaged(owner)
        local h = ttd:Track(owner or "A", "target")
        Fake.tick(12)
        Fake.event("PLAYER_REGEN_DISABLED")
        burn(14, 2)
        boss.health = 0.715
        Fake.tick(3)
        return h
    end

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        boss, add = { health = 1.0 }, { health = 1.0 }
        W.unit.target = boss
        Fake.plate("nameplate1", boss)
        Fake.plate("nameplate2", add)
        ttd = LibStub("LibTimeToDie-1.0")
        lhv = LibStub(LHV_MAJOR)
        assert.is_true(Fake.login())
    end)

    after_each(function()
        local errors = Fake.errors
        Fake.restore()
        assert.are.same({}, errors)
    end)

    it(
        "switching away moves the boss's life to its plate: same id, fed at 5%, the hand-over band no crossing",
        function()
            local h = engaged()
            local id0, n0 = id(h), row("target").crossings
            assert.is_number(id0)
            assert.are.equal("live", select(4, h:Get()))
            swap(add)
            assert.are_not.equal(id0, id(h)) -- the target holds the add's new life
            Fake.tick(12)
            assert.are.equal(6, source("nameplate1").bars) -- a 5% watch
            local est, lo, hi, state, _, pid = ttd:Get("A", "nameplate1")
            assert.are.equal(id0, pid)
            assert.are.equal("live", state) -- answering from its history while the plate primes and after
            assert.is_true(lo <= est and est <= hi)
            -- the plate's first band 70-75: its top is 3 above the last band's, its bottom below: no veto, and no crossing
            assert.are.equal(n0, row("nameplate1").crossings)
            burn(2, 2, 1) -- the boss reaches 67.5: the 65-70 cell, one crossing at 70
            assert.are.equal(n0 + 1, row("nameplate1").crossings)
            assert.are.same({ "nameplate1", id0 }, { ttd:Recent("A", 1) })
            assert.is_nil(ttd:Recent("A", 2))
        end
    )

    it("switching back resumes the boss's life the next frame with its id, and releases the plate's bars", function()
        local h = engaged()
        local id0 = id(h)
        swap(add)
        Fake.tick(12)
        burn(2, 2, 1)
        local n1 = row("nameplate1").crossings
        swap(boss)
        Fake.tick(1)
        local est, _, _, state, _, now = h:Get()
        assert.are.equal("live", state)
        assert.is_number(est)
        assert.are.equal(id0, now)
        assert.is_nil(source("nameplate1")) -- the target's 1% watch feeds it; the plate watch is gone
        assert.are.equal("nameplate2", (ttd:Recent("A", 1))) -- the add lost health: its life went to its plate
        assert.is_nil(ttd:Recent("A", 2))
        Fake.tick(12) -- the target's first band (67-68): the hand-over, never a crossing
        assert.are.equal(n1, row("target").crossings)
        burn(1.5, 2)
        assert.is_true(row("target").crossings > n1)
    end)

    it("a band whose bottom is 3 or more above the life's last top starts a new life (the veto)", function()
        local h = engaged()
        local id0 = id(h)
        swap(add)
        Fake.tick(12)
        burn(2, 2, 1) -- the plate's last band: 65-70
        boss.health = 0.905 -- healed in the frame of the switch back: the first 1% band is 90-91
        swap(boss)
        Fake.tick(12)
        local now = id(h)
        assert.is_number(now)
        assert.are_not.equal(id0, now)
    end)

    it("feeds every rise: a one-cell rise on the plate is a heal to the estimator", function()
        engaged()
        swap(add)
        Fake.tick(12)
        burn(2, 2, 1) -- 65-70 fed
        assert.is_true(row("nameplate1").crossings > 0)
        boss.health = 0.72 -- one 5% cell up: 70-75
        Fake.tick(3)
        assert.are.equal(0, row("nameplate1").crossings) -- fed: the heal rule restarted the fit
    end)

    it("the target event twice, or a mob cleared and targeted again, keeps its life and history", function()
        local h = engaged()
        local id0, n0 = id(h), row("target").crossings
        Fake.event("PLAYER_TARGET_CHANGED") -- the same unit
        Fake.tick(12)
        assert.are.same({ id0, n0 }, { id(h), row("target").crossings })
        assert.is_nil(source("nameplate1"))
        swap(nil) -- cleared
        Fake.tick(12)
        assert.are.equal(id0, select(6, ttd:Get("A", "nameplate1")))
        swap(boss)
        Fake.tick(12)
        assert.are.same({ id0, n0 }, { id(h), row("target").crossings })
    end)

    it("a plate token reused at once for another mob is untracked, and Recent skips it", function()
        engaged()
        swap(add)
        Fake.tick(12)
        Fake.plate("nameplate1", nil)
        local other = { health = 0.5 }
        Fake.plate("nameplate1", other) -- the same frame: another mob
        assert.are.same({ nil, nil, nil, "untracked" }, { ttd:Get("A", "nameplate1") })
        assert.is_nil(ttd:Recent("A", 1))
        assert.is_nil(source("nameplate1"))
        Fake.tick(12)
        swap(other) -- never the boss's life
        Fake.tick(12)
        assert.are.equal(0, row("target").crossings)
    end)

    it("a plate that appears for the target links after one read, unless a target change came first", function()
        local function onMob(tok)
            local mob = { health = 1.0 }
            swap(mob)
            Fake.tick(12)
            mob.health = 0.795
            Fake.tick(6)
            mob.health = 0.785
            Fake.tick(6)
            Fake.plate(tok, mob) -- queued: the link needs a read with no target change in between
            return mob
        end
        local h = ttd:Track("A", "target")
        Fake.event("PLAYER_REGEN_DISABLED")
        onMob("nameplate3")
        Fake.tick(12) -- the link's read
        local id0 = id(h)
        swap(add)
        assert.are.equal(id0, select(6, ttd:Get("A", "nameplate3")))
        onMob("nameplate4")
        swap(add) -- before the read: cancelled
        Fake.tick(12)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate4")))
    end)

    it("a secret UnitIsUnit links nothing", function()
        W.secretIsUnit = true
        engaged()
        swap(add)
        Fake.tick(12)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate1")))
        assert.is_nil(source("nameplate1"))
    end)

    it("no hand-off without a crossing, for a plainly dead mob, or with every owner opted out", function()
        ttd:Track("A", "target")
        Fake.tick(12)
        swap(add) -- the boss never lost a percent
        Fake.tick(12)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate1")))
        swap(boss)
        Fake.tick(12)
        burn(5, 2)
        boss.health, boss.dead = 0, true
        Fake.event("UNIT_HEALTH", "target")
        Fake.tick(2)
        swap(add)
        Fake.tick(12)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate1")))
        assert.are.same({ true }, { ttd:SetRecent("A", false) })
        boss.health, boss.dead = 0.9, nil
        swap(boss)
        Fake.tick(12)
        burn(5, 2)
        swap(add)
        Fake.tick(12)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate1")))
        assert.are.equal(1, nSources()) -- no plate watch
    end)

    it("an opted-out owner's record is dropped at the hand-off; the others move", function()
        engaged("A")
        ttd:Track("B", "target")
        burn(2, 2)
        ttd:SetRecent("A", false)
        swap(add)
        Fake.tick(12)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate1")))
        assert.is_number(select(6, ttd:Get("B", "nameplate1")))
        assert.is_nil(ttd:Recent("A", 1))
        assert.are.equal("nameplate1", (ttd:Recent("B", 1)))
    end)

    it("combat end and the cap of four release lazy lives, oldest first", function()
        local mobs = {}
        for i = 1, 6 do
            mobs[i] = { health = 1.0 }
            Fake.plate("nameplate" .. (i + 2), mobs[i])
        end
        local h = ttd:Track("A", "target")
        Fake.event("PLAYER_REGEN_DISABLED")
        local ids = {}
        for i = 1, 6 do
            swap(mobs[i])
            Fake.tick(12)
            mobs[i].health = 0.9
            Fake.tick(6)
            mobs[i].health = 0.89
            Fake.tick(6)
            ids[i] = id(h)
        end
        swap(add)
        Fake.tick(12)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate3"))) -- the oldest two went
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate4")))
        for i = 3, 6 do
            assert.are.equal(ids[i], select(6, ttd:Get("A", "nameplate" .. (i + 2))))
        end
        assert.are.same({ "nameplate8", ids[6] }, { ttd:Recent("A", 1) })
        assert.are.same({ "nameplate5", ids[3] }, { ttd:Recent("A", 4) })
        assert.is_nil(ttd:Recent("A", 5))
        assert.are.equal(5, nSources())
        Fake.event("PLAYER_REGEN_ENABLED")
        assert.is_nil(ttd:Recent("A", 1))
        assert.are.equal(1, nSources())
    end)

    it("switching back to the boss after four damaged adds resumes its life, and no add is evicted for it", function()
        local h = engaged("A")
        local id0 = id(h)
        local mobs = {}
        for i = 1, 4 do
            mobs[i] = { health = 1.0 }
            Fake.plate("nameplate" .. (i + 2), mobs[i])
            swap(mobs[i])
            Fake.tick(12)
            mobs[i].health = 0.9
            Fake.tick(6)
            mobs[i].health = 0.89
            Fake.tick(6)
        end
        assert.are.equal(id0, select(6, ttd:Get("A", "nameplate1")))
        swap(boss)
        Fake.tick(2)
        assert.are.equal(id0, id(h))
        for i = 1, 4 do
            assert.are_not.equal("untracked", select(4, ttd:Get("A", "nameplate" .. (i + 2))))
        end
    end)

    it("hints stay private to their owner across moves", function()
        ttd:HintBelow("A", 20, 2)
        engaged("A")
        ttd:Track("B", "target")
        burn(2, 2)
        swap(add)
        Fake.tick(12)
        assert.are.equal(20, row("nameplate1", "A").executePct)
        assert.is_nil(row("nameplate1", "B").executePct)
        swap(boss)
        Fake.tick(12)
        assert.are.equal(20, row("target", "A").executePct)
        assert.are.equal(2, row("target", "A").executeFactor)
        assert.is_nil(row("target", "B").executePct)
    end)

    it("an explicit plate track reads at 5% and shares the target's life while it is the target's plate", function()
        local h = engaged()
        local p = ttd:Track("A", "nameplate1")
        local q = ttd:Track("B", "nameplate2") -- not the target's: its own life, a cold start
        Fake.tick(12)
        for _, src in ipairs(lhv.sources) do
            if src.unit == "nameplate1" then
                assert.are.equal(5, (src.handles[1]:Domain()))
            end
        end
        assert.are.equal(id(h), id(p))
        assert.are_not.equal(id(h), id(q))
        local id0 = id(h)
        swap(add)
        Fake.tick(12)
        assert.are.equal(id0, id(p))
        assert.are.equal("live", (p:State()))
        assert.are.same({ "nameplate1", id0 }, { ttd:Recent("A", 1) })
        swap(boss)
        Fake.tick(12)
        assert.are.same({ id0, id0 }, { id(h), id(p) })
    end)

    it("5% answers are 1.1x wider while a plate feeds the life", function()
        engaged()
        swap(add)
        Fake.tick(12)
        burn(2, 2, 1)
        local _, lo, hi = ttd:Get("A", "nameplate1")
        local _, elo, ehi = ttd.byToken.nameplate1.life.byOwner.A.e:Get(GetTime())
        assert.is_true(math.abs(lo - elo / 1.1) < 1e-6 and math.abs(hi - ehi * 1.1) < 1e-6)
    end)

    it("a health read right after a target change is nil: nothing is fed to a new record", function()
        engaged("A")
        swap(add)
        ttd:Track("B", "target")
        Fake.event("PLAYER_REGEN_DISABLED")
        assert.is_false(ttd.byToken.target.life.byOwner.B.e.known)
        assert.is_false(ttd.byToken.target.life.byOwner.A.e.known)
    end)

    it("the new calls: Get by token, untracked, Recent, SetRecent, a sixth value", function()
        assert.are.same({ nil, nil, nil, "untracked" }, { ttd:Get("A", "focus") })
        assert.is_string(ttd:GetMessage("untracked"))
        assert.are.same({ nil, ttd.ERR.OWNER_INVALID }, { ttd:SetRecent(1, true) })
        assert.is_nil(ttd:Recent("A", 1))
        assert.are.same({ "LibTimeToDie-1.0", 5 }, { ttd:GetVersion() })
        local h = engaged()
        assert.are.equal(id(h), select(6, ttd:Get("A", "target")))
    end)

    it("an upgrade from minor 4 wraps the streams it holds in lives and passes the plate events' units", function()
        local h = engaged()
        local s = ttd.byToken.target
        -- what minor 4 left: records on the stream, no plates seen, an event dispatcher without the unit
        h.o, s.life, s.plate, ttd.plates = s.owners[1], nil, nil, nil
        ttd.onEvent = function(_, event)
            ttd.event(event)
        end
        ttd.frame:SetScript("OnEvent", ttd.onEvent)
        rawset(LibStub.minors, "LibTimeToDie-1.0", 4)
        Fake.loadTimeToDie()
        assert.are.same({ "LibTimeToDie-1.0", 5 }, { ttd:GetVersion() })
        local id0 = id(h)
        assert.is_number(id0)
        swap(add)
        Fake.tick(12)
        assert.are.equal(id0, select(6, ttd:Get("A", "nameplate1")))
        Fake.plate("nameplate1", nil)
        assert.are.equal("untracked", select(4, ttd:Get("A", "nameplate1")))
    end)

    it("a boss you never leave costs nothing: no plate watch, no identity reads, no allocation per frame", function()
        local calls, isUnit = 0, UnitIsUnit
        rawset(_G, "UnitIsUnit", function(...)
            calls = calls + 1
            return isUnit(...)
        end)
        local h = ttd:Track("A", "target", function() end)
        Fake.tick(12)
        Fake.event("PLAYER_REGEN_DISABLED")
        burn(5, 1, 1)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        calls = 0
        for _ = 1, 1200 do
            burn(1 / 60, 1, 1)
            h:Get()
        end
        local grew = collectgarbage("count") - before
        collectgarbage("restart")
        assert.are.equal(0, calls)
        assert.are.equal(1, nSources())
        assert.is_true(grew < 0.5, grew .. " KB")
    end)

    it("allocates nothing per frame with lazy lives, an explicit plate, sinks and the new calls", function()
        local third = { health = 1.0 }
        Fake.plate("nameplate3", third)
        local h = engaged()
        ttd:Track("B", "nameplate2", function() end)
        h:SetSink(function() end)
        Fake.tick(12)
        swap(add) -- the target takes the add's life from its tracked plate
        Fake.tick(12)
        burn(3, 1, 2)
        swap(third)
        Fake.tick(12)
        local function frame()
            boss.health, add.health = boss.health - 1 / 12000, add.health - 1 / 12000
            third.health = third.health - 1 / 6000
            Fake.tick(1)
            h:Get()
            ttd:Get("A", "nameplate1")
            ttd:Recent("A", 2)
        end
        for _ = 1, 300 do
            frame()
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1200 do
            frame()
        end
        local grew = collectgarbage("count") - before
        collectgarbage("restart")
        assert.are.same({ "nameplate2", "nameplate1" }, { ttd:Recent("A", 1), (ttd:Recent("A", 2)) })
        assert.is_true(grew < 0.5, grew .. " KB")
    end)
end)
