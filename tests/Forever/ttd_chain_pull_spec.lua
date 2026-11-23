-- tests/Forever/ttd_chain_pull_spec.lua (ttd-chain-pull; lane B8, L1730, L1736): the next target does not take the last
-- one's kill time, and the first answers on a new target are the library's own. The real LibTimeToDie (vendored v0.4.0,
-- minor 4) over the fake bands (ttd_rig.lua), through the core's fight_remains, target.time_to_die and time to a
-- percent. vendor-libs removed B8's forget at the pull and its 0.5 s keep; a seed still reads unknown (the fight runs).
local headless = require("Game.harness.headless")
local fake_lhv = require("Game.harness.fake_lhv")
local ttd_rig = require("Game.harness.ttd_rig")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

local UNKNOWN, TICK = 3600, 0.1

-- `nilForNone`: UnitExists answers nil for no unit, not false
local function boot(nilForNone)
    local new = fake.new
    if nilForNone then
        fake.new = function(...) -- before the facade resolves UnitExists
            local api, ctl = new(...)
            local exists = api.UnitExists
            api.UnitExists = function(unit)
                local e = exists(unit)
                if e == fake.SECRET or e then
                    return e
                end
            end
            return api, ctl
        end
    end
    local ok, H = pcall(headless.new, { character = ww.character(), pack = ww.PACK })
    fake.new = new
    assert(ok, H)
    assert.are.same({}, H.loadErrors)
    local ctl = H.ctl
    local bands = fake_lhv.new({
        now = function()
            return ctl.now
        end,
    })
    local major, minor = bands:GetVersion()
    local stub = rawget(H.env, "LibStub")
    stub.libs[major], stub.minors[major] = bands, minor
    local rig = ttd_rig.install(H, bands)
    local w = { H = H, tracks = 0 }
    local track = rig.lib.Track
    function rig.lib.Track(...)
        w.tracks = w.tracks + 1
        return track(...)
    end

    function w.read()
        local st = H.Hekili.State
        st.reset()
        return st.fight_remains, st.target.time_to_die
    end

    function w.step()
        ctl.now = ctl.now + TICK
        ttd_rig.poll(rig)
    end

    function w.health(pct)
        bands:Push("health", "target", nil, 12 * pct, 1200, ctl.now)
    end

    -- the client's target change: the hidden-value library hears it first
    function w.target(guid, pct, dead)
        ctl.exists.target, ctl.guid.target, ctl.dead.target = true, guid, dead
        bands:Prime("target", ctl.now)
        if dead then
            bands:Push("health", "target", nil, nil, nil, ctl.now)
        else
            w.health(pct)
        end
        H.Fire("PLAYER_TARGET_CHANGED")
    end

    -- the client clears the target a few ms after a kill, as at a deselect
    function w.none()
        ctl.exists.target, ctl.guid.target, ctl.dead.target = false, nil, nil
        bands:Push("health", "target", nil, nil, nil, ctl.now)
        H.Fire("PLAYER_TARGET_CHANGED")
    end

    -- the hidden-value library primes the target's source again with no target change (a desync)
    function w.prime()
        bands:Prime("target", ctl.now)
    end

    function w.combat(on)
        ctl.combat = on
        H.Fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end

    function w.wait(seconds)
        for _ = 1, math.floor(seconds / TICK + 0.5) do
            w.step()
        end
    end

    -- the target falls from `from` percent by `rate` a second; returns the last answers
    function w.fight(from, rate, seconds, each)
        local remains, ttd
        for i = 1, math.floor(seconds / TICK + 0.5) do
            w.step()
            w.health(from - rate * i * TICK)
            remains, ttd = w.read()
            if each then
                each(i * TICK, remains, ttd)
            end
        end
        return remains, ttd
    end

    ctl.exists.target, ctl.guid.target = false, nil
    ctl.inRange.target, ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    H.Hekili.bandOff = false
    return w
end

-- A first mob killed in `kill` seconds; its time was read as short.
local function killFirst(w, kill)
    w.target("Creature-1", 100)
    w.read()
    w.wait(0.5)
    w.combat(true)
    local remains, ttd = w.fight(100, 100 / kill, kill - TICK)
    assert.is_true(remains < 30 and ttd < 30)
end

-- A full 120 s mob: never under 30 s in its first 5 s (unknown is fine), and an estimate by 8 s.
local function tough(w)
    w.combat(true)
    local short = {}
    local remains, ttd = w.fight(100, 100 / 120, 8, function(at, r, t)
        if at <= 5 + 1e-6 and (r < 30 or t < 30) then
            short[#short + 1] = ("%.1f s: %.1f, %.1f"):format(at, r, t)
        end
    end)
    assert.are.same({}, short)
    assert.is_true(remains >= 30 and remains < UNKNOWN and ttd >= 30 and ttd < UNKNOWN)
end

describe("ttd-chain-pull: the next mob does not take the last one's kill time (lane B8, L1730)", function()
    for _, kill in ipairs({ 6, 15 }) do
        for _, gap in ipairs({ 1, 5, 9 }) do
            it(("a %d s kill, %d s, then a full 120 s mob: never under 30 s"):format(kill, gap), function()
                local w = boot()
                killFirst(w, kill)
                w.none()
                w.combat(false)
                w.wait(gap) -- nothing reads the estimate in the gap
                w.target("Creature-2", 100)
                tough(w)
            end)
        end

        it(
            ("a %d s kill, the next pull within the keep: priming does not bring the old value back"):format(kill),
            function()
                local w = boot()
                killFirst(w, kill)
                w.none()
                w.step()
                w.target("Creature-2", 100)
                assert.are.same({ UNKNOWN, UNKNOWN }, { w.read() })
                tough(w)
            end
        )
    end

    -- Past the library's carry age (10 s) it drops the slope itself, so the track stays and with it the learned execute
    -- factor. e16716e84's answers 5 s into each of four mobs that die 2.4 times as fast below the hinted 20 percent.
    for _, gap in ipairs({ 11, 30 }) do
        it(("pulls %d s apart keep the learned execute factor"):format(gap), function()
            local w = boot()
            w.H.ns.TtdHintsChanged()
            local at5 = {}
            for mob = 1, 4 do
                w.target("Creature-" .. mob, 100)
                w.H.Hekili:GetTTD("target")
                w.wait(0.5)
                w.combat(true)
                local pct, i = 100, 0
                while pct > 1 do
                    i = i + 1
                    pct = pct - (pct > 20 and 0.25 or 0.6)
                    w.step()
                    w.health(math.max(pct, 0.5))
                    local ttd = w.H.Hekili:GetTTD("target")
                    if i == 50 then
                        at5[mob] = ("%.0f"):format(ttd)
                    end
                end
                w.none()
                w.combat(false)
                w.wait(gap - 2)
                w.H.Fire("PLAYER_TARGET_CHANGED") -- still none: gone since the kill, not since this
                w.wait(2)
            end
            assert.are.same({ "35", "32", "31", "31" }, at5)
            assert.are.equal(1, w.tracks)
        end)
    end

    it("no unit answered nil, not false: forgotten all the same", function()
        local w = boot(true)
        killFirst(w, 6)
        w.none()
        w.wait(1)
        w.target("Creature-2", 100)
        tough(w)
    end)

    it("the cleared corpse selected again, then a pull: forgotten", function()
        local w = boot()
        killFirst(w, 6)
        w.none()
        w.wait(1)
        w.target("Creature-1", 0, true)
        w.wait(1)
        w.target("Creature-2", 100)
        tough(w)
    end)

    -- A plainly dead corpse is gone to the library (w.target's dead: no health), so a dwell does not keep the carry
    -- fresh: past 10 s the library drops the rate itself and the track stays.
    for _, case in ipairs({ { 12 }, { 30 }, { 15, cleared = true } }) do
        local first = case.cleared and "none, then the corpse again" or "a targeted corpse"
        it(("%s, %d s, then a pull: never under 30 s, the track kept"):format(first, case[1]), function()
            local w = boot()
            killFirst(w, 6)
            if case.cleared then
                w.none()
                w.wait(1)
            end
            w.target("Creature-1", 0, true)
            w.combat(false)
            w.wait(case[1])
            w.target("Creature-2", 100)
            tough(w)
            assert.are.equal(1, w.tracks)
        end)
    end

    it("a secret identity cannot be told from the last mob's: forgotten", function()
        local w = boot()
        killFirst(w, 6)
        w.none()
        w.wait(1)
        w.target(fake.SECRET, 100)
        tough(w)
    end)

    -- The same living mob targeted again (fight_remains/target.time_to_die at 0, 0.1, 0.5, 1, 3 and 5 s). e16716e84
    -- kept the mob's countdown for its first reads (the 0.2 s deselect: 13.9, 13.8). vendor-libs: nothing is kept across
    -- a target change, and LibTimeToDie minor 4 answers the re-primed stream only after 1.5 s of loss, then its fit.
    local KEPT = {
        { "a deselect of 0.2 s", 0.2 },
        { "a deselect of 5 s", 5 },
        { "a look at another mob", 0.5, other = "Creature-2" },
    }
    for _, case in ipairs(KEPT) do
        it(("the same mob targeted again after %s: unknown, then its own fit"):format(case[1]), function()
            local w = boot()
            w.target("Creature-1", 100)
            w.read()
            w.wait(0.5)
            w.combat(true)
            w.fight(100, 5, 6)
            if case.other then
                w.target(case.other, 100)
            else
                w.none()
            end
            w.wait(case[2])
            w.target("Creature-1", 70)
            w.H.Fire("PLAYER_TARGET_CHANGED") -- twice a swap
            local seen = { ("%.1f/%.1f"):format(w.read()) }
            w.fight(70, 5, 5, function(at, r, t)
                local ms = math.floor(at * 1000 + 0.5)
                if ms == 100 or ms == 500 or ms == 1000 or ms == 3000 or ms == 5000 then
                    seen[#seen + 1] = ("%.1f/%.1f"):format(r, t)
                end
            end)
            assert.are.equal(
                "3600.0/3600.0 3600.0/3600.0 3600.0/3600.0 3600.0/3600.0 11.1/11.1 9.1/9.1",
                table.concat(seen, " ")
            )
            assert.are.equal(1, w.tracks)
        end)
    end

    -- vendor-libs: the core's forget at the pull (TTD_CARRY) is gone; the library forgets the last mob itself.
    it("one track: no target change, corpse, repeated event or read releases it", function()
        local w = boot()
        killFirst(w, 6)
        w.target("Creature-2", 100)
        w.none()
        w.H.Fire("PLAYER_TARGET_CHANGED")
        w.read()
        w.target("Creature-3", 0, true)
        w.read()
        w.target("Creature-4", 100)
        w.H.Fire("PLAYER_TARGET_CHANGED")
        w.read()
        w.read()
        assert.are.equal(1, w.tracks)
    end)

    -- L1730's straight swaps, B8's "the library's part": now pinned through the core.
    it("a kill with no target event, then a straight swap to a full 120 s mob: never under 30 s", function()
        local w = boot()
        killFirst(w, 6)
        w.health(0.5)
        w.step()
        w.target("Creature-2", 100)
        tough(w)
    end)

    it("a direct swap in combat to a tough mob first seen at 70%: never under half its time", function()
        local w = boot()
        killFirst(w, 6)
        w.target("Creature-2", 70)
        local under = {}
        w.fight(70, 70 / 84, 10, function(at, r, t)
            local truth = 84 - at
            if (r < UNKNOWN and r < truth / 2) or (t < UNKNOWN and t < truth / 2) then
                under[#under + 1] = ("%.1f s: %.1f, %.1f"):format(at, r, t)
            end
        end)
        assert.are.same({}, under)
    end)

    it("reads with no target allocate nothing and track nothing", function()
        local w = boot()
        killFirst(w, 6)
        w.none()
        local hk = w.H.Hekili
        hk:GetGreatestTTD()
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            hk:GetTTD("target")
            hk:GetGreatestTTD()
        end
        local after = collectgarbage("count")
        collectgarbage("restart")
        assert.are.equal(before, after)
        assert.are.equal(1, w.tracks)
    end)
end)

-- L1736 (vendor-libs): LibTimeToDie minor 4's first answers, through the core; B8's "a seed reads unknown" stays.
-- Minor 4 answers a new stream (a pull, a swap, a re-target) only once it spans 1.5 s, and carries no last-target rate
-- before that. Live, B8's seed read 3.63 s at 72%, then 52 s.
describe("ttd-first-guess: the library's first answers through the core (L1736)", function()
    -- the library's state and reason, from the snapshot's line
    local function reason(w)
        return w.H.Hekili:GetTTDInfo():match("^time to die: (%S+) (%S+)")
    end

    -- runs of "reason: answer" over the reads, answer "known" when fight_remains, target.time_to_die and the time to
    -- 35% all answer, "3600" when all three are unknown, else the three; `short`: target.time_to_die under 30 s;
    -- `under`: with `truth(i)` (the true time left), fight_remains or target.time_to_die under half of it; `low`: the
    -- lowest fight_remains over the true time
    local function runs(w, ticks, hit, truth)
        local out, last, n = {}, nil, 0
        local short, under, low = {}, {}, math.huge
        for i = 1, ticks do
            w.step()
            hit(i)
            local r, t = w.read()
            local p = w.H.Hekili:GetTimeToPct("target", 35)
            local s, why = reason(w)
            local key
            if r < UNKNOWN and t < UNKNOWN and p < UNKNOWN then
                key = "known"
            elseif r == UNKNOWN and t == UNKNOWN and p == UNKNOWN then
                key = "3600"
            else
                key = ("%.1f/%.1f/%.1f"):format(r, t, p)
            end
            key = (s == "live" and why or s) .. ": " .. key
            if key == last then
                n = n + 1
            else
                if last then
                    out[#out + 1] = last .. " x" .. n
                end
                last, n = key, 1
            end
            if t < 30 then
                short[#short + 1] = ("%.1f s: %s %.1f"):format(i * TICK, why, t)
            end
            local tr = truth and truth(i)
            if tr and ((r < UNKNOWN and r < tr / 2) or (t < UNKNOWN and t < tr / 2)) then
                under[#under + 1] = ("%.1f s: %s %.1f/%.1f, true %.1f"):format(i * TICK, why, r, t, tr)
            end
            if tr and r < UNKNOWN then
                low = math.min(low, r / tr)
            end
        end
        out[#out + 1] = last .. " x" .. n
        return table.concat(out, ", "), short, under, low
    end

    local function pull(w)
        w.target("Creature-1", 100)
        w.read()
        w.wait(0.5)
        w.combat(true)
    end

    -- a 20 s mob fought 6 s, then a direct swap in combat to a full one
    local function swap(w)
        pull(w)
        w.fight(100, 5, 6)
        w.target("Creature-2", 100)
    end

    it(
        "a mob first seen at 78%, one hit to 72% after the pull: unknown until the fit, then the fit's answer",
        function()
            local w = boot()
            w.target("Creature-1", 78)
            w.read()
            w.wait(0.3)
            w.combat(true)
            w.wait(0.2)
            w.health(72)
            local seen, short = runs(w, 40, function(i)
                if i > 1 then
                    w.health(72 - 1.3 * (i - 1) * TICK)
                end
            end)
            -- minor 2 published a seed of 2.5 s here (true about 55); B8's core rule read it unknown
            assert.are.equal("unknown: 3600 x17, fit: known x23", seen)
            assert.are.same({}, short)
        end
    )

    it("a direct swap in combat: unknown until the new mob's fit, nothing kept from the last", function()
        local w = boot()
        swap(w)
        local seen = runs(w, 40, function(i)
            if i > 15 then
                w.health(100 - 5 * (i - 15) * TICK)
            end
        end)
        -- minor 2 + B8: the last mob's fight_remains kept 0.1 s, its rate as prior 1.7 s, then 1.6 s of seed read unknown
        assert.are.equal("priming: 3600 x1, unknown: 3600 x33, fit: known x6", seen)
        assert.are.equal(1, w.tracks)
    end)

    -- Fable m1 (a): B8's prior carried an opener's seed to the next mob (0.5 s, then 0.001 s).
    it(
        "an opener hit 100 to 72% in 0.2 s, then a direct swap to a full 120 s mob: never under half its time",
        function()
            local w = boot()
            pull(w)
            w.step()
            w.health(86)
            w.step()
            w.health(72)
            w.target("Creature-2", 100)
            local seen, _, under = runs(w, 120, function(i)
                if i > 5 then
                    w.health(100 - (100 / 120) * (i - 5) * TICK)
                end
            end, function(i)
                return 120 - math.max(0, i - 5) * TICK
            end)
            assert.are.equal("priming: 3600 x1, unknown: 3600 x41, seed: 3600 x12, fit: known x66", seen)
            assert.are.same({}, under)
        end
    )

    -- Fable m1 (b), its stall.lua: B8 read stalled 0.01 s through the lull, then a prior of 2.9-2.3 s.
    it("three quick crossings to 90%, a 6 s lull, then a 60 s rate: never under half the time", function()
        local w = boot()
        pull(w)
        w.health(99)
        local seen, _, under = runs(w, 140, function(i)
            if i == 2 then
                w.health(97.5)
            elseif i == 3 then
                w.health(90.5)
            elseif i > 63 and (i - 63) % 6 == 0 then
                w.health(90.5 - (i - 63) / 6)
            end
        end, function(i)
            return 54 + math.max(0, 63 - i) * TICK
        end)
        assert.are.equal("unknown: 3600 x87, fit: known x53", seen)
        assert.are.same({}, under)
    end)

    -- Fable I1: B8's rule blanked a re-seed after a speed-up. Minor 4 seeds no more after a fit, so the rule finds no
    -- seed there; the blank is the
    -- library's own (its README: up to 1.5 s after a sudden speed-up), unchanged by the core.
    it("a 60 s kill that speeds up x2.5 below 20%: fit, about 1 s unknown, fit; never a seed", function()
        local w = boot()
        pull(w)
        local pct = 100
        local seen = runs(w, 520, function()
            pct = pct - (pct > 20 and 100 / 60 or 2.5 * 100 / 60) * TICK
            w.health(pct)
        end)
        assert.are.equal("unknown: 3600 x24, fit: known x464, unknown: 3600 x9, fit: known x23", seen)
    end)

    -- A same-unit re-prime (a desync: the hidden-value library primes the source again) keeps the estimate.
    it("a re-prime of the target mid-fight: fight_remains keeps answering", function()
        local w = boot()
        pull(w)
        local seen = runs(w, 60, function(i)
            if i == 40 then
                w.prime()
            end
            w.health(100 - 2 * i * TICK)
        end)
        assert.are.equal("unknown: 3600 x21, fit: known x39", seen)
    end)

    -- Why the seed rule stays (L1736): a burst then a fall 56 times slower gives a seed of about half the time for its 2 s
    -- (0.52 of it; without the rule it answered), then a fit still short, at a pull and on a target taken in combat
    -- alike. The rule reads the seed's 2 s unknown and
    -- passed the same fit. The library's lab counted streams with a short read in such classes (opener bursts, lumpy
    -- hits) within one in 180 fights of B8's rule.
    local RESIDUE = {
        { "at a pull", pull, 1, "unknown: 3600 x22, seed: 3600 x20, fit: known x18" },
        {
            "after a direct swap in combat",
            swap,
            2,
            "priming: 3600 x1, unknown: 3600 x22, seed: 3600 x20, fit: known x17",
        },
    }
    for _, case in ipairs(RESIDUE) do
        it(("a 28%% hit %s, then 0.5%% a second: the seed reads unknown, the fit"):format(case[1]), function()
            local w = boot()
            case[2](w)
            local at = case[3]
            local seen, _, under, low = runs(w, 60, function(i)
                if i == at then
                    w.health(72)
                elseif i > at then
                    w.health(72 - 0.5 * (i - at) * TICK)
                end
            end, function(i)
                return (72 - 0.5 * math.max(0, i - at) * TICK) / 0.5
            end)
            assert.are.equal(case[4], seen)
            assert.are.same({}, under)
            assert.are.equal("0.74", ("%.2f"):format(low)) -- the fit's, never the seed's 0.52
        end)
    end
end)
