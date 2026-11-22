-- tests/Forever/ttd_chain_pull_spec.lua (ttd-chain-pull; lane B8, L1730): the pull after a target that is gone does not
-- take that target's kill time. The real LibTimeToDie over the fake bands (ttd_rig.lua), through the core's
-- fight_remains and target.time_to_die. A direct swap in combat, a swap from a dying mob to a tough one first seen
-- below full, and one straight from a mob that died targeted with no target event or a secret death, are the
-- library's part: not pinned here.
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

describe("ttd-chain-pull: time to die forgets the last mob at a pull (lane B8, L1730)", function()
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

    -- The answers of e16716e84, recorded there (fight_remains/target.time_to_die): the same living mob targeted again
    -- keeps them, after a deselect or a look at another mob. Except its reads at 0.5 and 1.0 s, now 3600/3600 (L1742):
    -- they are the re-primed stream's seed, which reads unknown (L1736). This rig's constant slope makes its seeds
    -- accurate (13.6, 13.1 here); live seeds are not, so every seed reads unknown until a fit.
    local KEPT = {
        {
            "a deselect of 0.2 s",
            0.2,
            answers = "13.9/3600.0 13.8/3600.0 3600.0/3600.0 3600.0/3600.0 11.1/11.1 9.1/9.1",
        },
        {
            "a deselect of 5 s",
            5,
            answers = "3600.0/3600.0 3600.0/3600.0 3600.0/3600.0 3600.0/3600.0 11.1/11.1 9.1/9.1",
        },
        {
            "a look at another mob",
            0.5,
            other = "Creature-2",
            answers = "3600.0/3600.0 3600.0/3600.0 3600.0/3600.0 3600.0/3600.0 11.1/11.1 9.1/9.1",
        },
    }
    for _, case in ipairs(KEPT) do
        it(("the same mob targeted again after %s keeps its answers"):format(case[1]), function()
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
            assert.are.equal(case.answers, table.concat(seen, " "))
            assert.are.equal(1, w.tracks)
        end)
    end

    it("a track once a pull: not at a direct swap, a repeated event, a corpse, no target or a read", function()
        local w = boot()
        killFirst(w, 6)
        w.target("Creature-2", 100) -- a direct swap: the library's part
        assert.are.equal(1, w.tracks)
        w.none()
        w.H.Fire("PLAYER_TARGET_CHANGED")
        w.read()
        w.target("Creature-3", 0, true)
        w.read()
        assert.are.equal(1, w.tracks)
        w.target("Creature-4", 100)
        assert.are.equal(2, w.tracks) -- at the change, so the new mob is timed before anything reads it
        w.H.Fire("PLAYER_TARGET_CHANGED")
        w.read()
        w.read()
        assert.are.equal(2, w.tracks)
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

-- L1736, owner's A (L1742): a seed (the stream's first hits over the time since its anchor) reads unknown until the
-- library answers from a fit or a prior. Live a pull's seed is wildly short (3.63 s at 72%, then 52 s).
describe("ttd-seed: the library's first guess reads unknown (lane B8, L1736)", function()
    -- the library's state and reason, from the snapshot's line
    local function reason(w)
        return w.H.Hekili:GetTTDInfo():match("^time to die: (%S+) (%S+)")
    end

    -- runs of "reason: answer" over the reads, answer "known" when fight_remains, target.time_to_die and the time to
    -- 35% all answer, "3600" when all three are unknown, else the three
    local function runs(w, ticks, hit)
        local out, last, n = {}, nil, 0
        local short = {}
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
        end
        out[#out + 1] = last .. " x" .. n
        return table.concat(out, ", "), short
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
            assert.are.equal("seed: 3600 x17, fit: known x23", seen)
            assert.are.same({}, short) -- the seed read 2.5 s, true about 55
        end
    )

    it("a direct swap in combat: the prior answers, its seed reads unknown about 1.6 s, then the fit", function()
        local w = boot()
        w.target("Creature-1", 100)
        w.read()
        w.wait(0.5)
        w.combat(true)
        w.fight(100, 5, 6)
        w.target("Creature-2", 100)
        local seen = runs(w, 40, function(i)
            if i > 15 then
                w.health(100 - 5 * (i - 15) * TICK)
            end
        end)
        -- priming: the last mob's fight_remains, kept 0.1 s (I1); the prior (its rate carried); 1.6 s of seed
        assert.are.equal("priming: 14.0/3600.0/3600.0 x1, prior: known x17, seed: 3600 x16, fit: known x6", seen)
        assert.are.equal(1, w.tracks)
    end)
end)
