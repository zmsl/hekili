-- tests/Forever/loop_bands_spec.lua (LibHiddenValues integration design 5.4, 6.1 lanes B1-B2): the `bands` arm. The
-- driver's belief watches through fake_lhv.lua (loop.lua), the observer pushing the world's truth. The target health
-- family reads its band (lane B2); no priority of these packs reads target health (their low-health lines are the
-- client's own usability gates), so on the bands-health arm (no power band) every output of a fight still equals the
-- default arm's on the same seed. The resources read theirs (lane B4): on the bands arms the outputs move, and the
-- believed floor is above the truth on no more polls than the default arm's (the L1525 ratchet, in each lead arm). At every
-- fold the truth lies inside the band the family applied, or the band lagged it (loop.bandCheck: containment, L1666 a),
-- on each channel the world has; what the family made of it, clipped, holds the truth too, and its estimate lies
-- within one band of the truth (`est`).
local loop = require("Game.harness.loop")
local ab = require("Game.harness.ab")
local ww = require("Forever.helpers.warrior_world")
local dlw = require("Forever.helpers.druid_loop_world")
local mw = require("Forever.helpers.mage_world")
local pw = require("Forever.helpers.paladin_world")

-- The outputs the gates read from a run (loop.run's record), and the bands arm's lines.
local ROWS = { "ours", "pressed", "presses", "pressedBy", "refused", "gap", "readyShort", "heldReady", "loOver", "up" }

local function fight(content, arm, seed, plant, duration)
    local L, lines, check = loop.new(content), {}, ab.check
    if plant then
        plant(L.us.ns.VirtualStateInternal, L.us.ns.VirtualState.Obs)
    end
    ab.check = function(ok, label, line) -- the lines a record-only arm writes to .ab/<arm>.tsv
        lines[#lines + 1] = label .. " " .. tostring(line)
        if not plant then -- a planted family's run is read below, never asserted here
            return check(ok, label, line, "default")
        end
    end
    local ok, run = pcall(loop.run, L, seed, { duration = duration or 30, arm = arm }, { { H = L.us } })
    ab.check = check
    assert(ok, run)
    assert.are.same({ 0, 0 }, { run.errors, run.raises })
    return run, L.us, lines
end

describe("the bands arm #slow", function()
    for _, case in ipairs({
        { "Arms (rage)", ww, { -1, 0, 1 } },
        { "Feral (energy; mana and rage while not shown are paused)", dlw.Feral, { -1, 0 } },
        { "Frost (mana)", mw.Frost, { -1, 0 } },
    }) do
        it(
            case[1] .. ": the health bands alone leave the rows; each applied band holds the truth or lagged it",
            function()
                local base = fight(case[2], "default", 3)
                local health = fight(case[2], "bands-health", 3)
                for _, key in ipairs(ROWS) do
                    assert.are.same(base[key], health[key], key)
                end
                for _, arm in ipairs({ "bands-lead", "bands-lag", "bands-spend-first", "bands-spend-late" }) do
                    local lead = fight(case[2], arm, 3)
                    assert.is_true(
                        lead.loOver <= base.loOver,
                        ("%s: lo over %d, default %d"):format(arm, lead.loOver, base.loOver)
                    )
                end
                local run, H, lines = fight(case[2], "bands", 3)
                assert.is_true(run.loOver <= base.loOver, ("lo over %d, default %d"):format(run.loOver, base.loOver))
                local b = run.bands
                assert.are.same({}, b.misses)
                assert.are.equal(b.checked, b.held + b.lagged) -- held at the fold, or lagged: its own row (L1666 a)
                local e = b.est -- the target's estimate within one band of the truth wherever its family applied one
                assert.is_true(e.n > 20, tostring(e.n))
                assert.are.same({}, e.offs)
                assert.are.equal(0, e.off + e.outside)
                assert.are.equal(e.n, e.within + e.lagged + e.floored)
                for _, ch in ipairs(case[3]) do
                    assert.is_true((b.live[ch] or 0) > 20, ch .. " " .. tostring(b.live[ch]))
                end
                local I = H.ns.VirtualStateInternal
                local powers = 0
                for ch, n in pairs(b.live) do
                    powers = powers + (ch > 0 and n > 20 and 1 or 0)
                    assert.is_number(I.bandDisagree[ch], ch)
                end
                assert.is_true(powers >= 1, "a power band") -- the class's own power, in points
                assert.is_truthy(
                    lines[#lines]:match("^bands seed 3 checked %d+ held %d+ lagged %d+ live .* est %d+ "),
                    lines[#lines]
                )
            end
        )
    end

    -- (review I4) whole fights, through the low-health part where the gate's answers meet the band and the resource runs
    -- short: what the family made of the band after the clip
    for _, case in ipairs({ { "Arms", ww, 5 }, { "Retribution", pw.Retribution, 1 } }) do
        it(case[1] .. " to the kill: the clipped interval holds the truth, no estimate off", function()
            local b = fight(case[2], "bands", case[3], nil, 180).bands
            assert.are.same({}, b.est.offs)
            assert.are.same({ 0, 0, 0 }, { b.missed, b.est.off, b.est.outside })
        end)
    end

    -- The check reads what the family applied, not what the source logged: a planted family that records its band one
    -- cell high fails it.
    it("a family applying a band off the truth fails the containment check", function()
        local run = fight(ww, "bands", 3, function(I, Obs)
            I.On(Obs.Band, function(o) -- after the family's own handler (registered at load)
                if o.a == -1 and o.b <= o.c then
                    I.bandUsedLo[-1], I.bandUsedHi[-1] = o.b + 0.02, o.c + 0.02
                end
            end)
        end)
        assert.is_true(run.bands.missed > 20, tostring(run.bands.missed))
        assert.is_truthy(run.bands.misses[1]:match("^%-1 at "), run.bands.misses[1])
    end)

    -- The gate's path (loop.tally): three fights on one boot, run A with the oracle shadow, run B, the 30 s gap between
    -- fights (the idle pause), the fake and its history carried into each new world, a kill's gone, the next prime.
    local function tally(arm)
        local L, lines, check = loop.new(ww), {}, ab.check
        ab.check = function(ok, label, line)
            lines[#lines + 1] = label == "bands" and line or nil
            return true -- record-only: the rows are compared below
        end
        local ok, m = pcall(loop.tally, L, 3, { arm = arm })
        ab.check = check
        assert(ok, m)
        return m, lines
    end

    it("three fights on one boot: health alone the default's tally, every fight's bands holding the truth", function()
        local base = tally("default")
        local m = tally("bands-health")
        local bands, lines = tally("bands")
        assert.is_true(bands.loOver <= base.loOver, ("lo over %d, default %d"):format(bands.loOver, base.loOver))
        for _, key in ipairs({ "fights", "both", "agree", "conf", "react", "refused", "attempts", "episodes" }) do
            assert.are.same(base[key], m[key], key)
        end
        for _, key in ipairs({ "readyShort", "heldReady", "loOver", "A", "B", "gap", "selfCheck", "pressedBy" }) do
            assert.are.same(base[key], m[key], key)
        end
        assert.are.equal(3, #lines) -- run A's driver only: never the oracle, never run B
        for f, line in ipairs(lines) do
            local checked, held, lagged = line:match("checked (%d+) held (%d+) lagged (%d+)")
            assert.are.equal(tonumber(checked), held + lagged, line)
            assert.is_truthy(line:match(" off 0 outside 0 "), line)
            for _, ch in ipairs({ "-1", "0", "1" }) do
                local n = tonumber(line:match("[ ,]" .. ch .. ":(%d+)"))
                assert.is_true((n or 0) > 100, f .. ": " .. line)
            end
        end
    end)

    it("bands-drop: the capability lost mid-fight, no floor more over, no band logged after it", function()
        local base = fight(ww, "default", 5)
        local run, H = fight(ww, "bands-drop", 5)
        assert.is_true(run.loOver <= base.loOver, ("lo over %d, default %d"):format(run.loOver, base.loOver))
        local I = H.ns.VirtualStateInternal
        for _, live in pairs(I.bandLive) do
            assert.is_false(live)
        end
        assert.are.equal(run.bands.checked, run.bands.held + run.bands.lagged)
        assert.is_true(run.bands.checked > 0)
    end)

    -- L1666 d: the real library keeps an "error" loss for the session (design 5.2), so the next fights start without.
    it("bands-drop over three fights: the capability lost with error stays lost, no band in fights 2 and 3", function()
        local _, lines = tally("bands-drop")
        assert.are.equal(3, #lines)
        assert.is_truthy(lines[1]:match("checked [1-9]"), lines[1])
        for f = 2, 3 do
            assert.is_truthy(lines[f]:match("checked 0 "), lines[f])
        end
    end)
end)

-- (review I4, M4) loop.bandCheck on planted drains: the band and what the family made of it are checked apart.
describe("the bands arm's containment check", function()
    local LATENCY = 7 / 60 -- the fake library's h:Latency()
    local NOW = 10

    -- truth now, `was` until `left` seconds ago; the band `age` seconds old as applied; est and iv: the family's
    local function check(o)
        local lo, hi = o.band[1], o.band[2]
        local VI = {
            TARGET_HEALTH_FLOOR = 0.02,
            bandLive = { [-1] = true },
            bandUsed = { [-1] = o.used or 2 },
            bandUsedLo = { [-1] = lo },
            bandUsedHi = { [-1] = hi },
            bandLo = { [-1] = lo },
            bandHi = { [-1] = hi },
            bandT = { [-1] = NOW - (o.age or 0) },
        }
        local iv = o.iv or o.band
        local health = { est = o.est, lo = iv[1], hi = iv[2] }
        local function Health()
            return health
        end
        local H = { ns = { VirtualStateInternal = VI, VirtualState = { Health = Health } }, ctl = { now = NOW } }
        local lhv = {}
        function lhv.TruthAt(_, _, _, _, t)
            return t >= NOW - (o.left or 0) and o.truth or o.was or o.truth, 1
        end
        local e = { n = 0, within = 0, lagged = 0, floored = 0, off = 0, outside = 0, worst = 0, offs = {} }
        local b = { checked = 0, held = 0, lagged = 0, missed = 0, live = {}, misses = {}, used = {}, est = e }
        b.used[-1] = o.before
        loop.bandCheck({ bands = b }, H, lhv)
        return { b.checked, b.held, b.lagged, b.missed, e.lagged, e.floored, e.off, e.outside }
    end

    it("a frozen band is missed; a still one whose truth left it within the Latency lags", function()
        local o = { band = { 0.6, 0.61 }, est = 0.605, truth = 0.05, was = 0.605, age = 8, left = 5, before = 1 }
        assert.are.same({ 1, 0, 0, 1, 0, 0, 1, 1 }, check(o))
        o.left = LATENCY / 2 -- the same old stamp
        assert.are.same({ 1, 0, 1, 0, 1, 0, 0, 0 }, check(o))
    end)

    it("an interval off the truth is seen though its band holds", function()
        local o = { band = { 0.15, 0.16 }, iv = { 0.9, 1 }, est = 0.155, truth = 0.155, before = 1 }
        assert.are.same({ 1, 1, 0, 0, 0, 0, 0, 1 }, check(o))
    end)

    it("a lagging band covers no error larger than its own", function()
        local o = { band = { 0.11, 0.12 }, est = 0.21, truth = 0.1, was = 0.115, age = 0.1, left = 0.05, before = 1 }
        o.iv = { 0.21, 0.21 }
        assert.are.same({ 1, 0, 1, 0, 0, 0, 1, 1 }, check(o))
        o.band, o.was, o.truth = { 0.25, 0.26 }, 0.255, 0.18
        o.est, o.iv = 0.2, { 0.2, 0.2 } -- clipped toward the truth
        assert.are.same({ 1, 0, 1, 0, 1, 0, 0, 0 }, check(o))
    end)

    it("floored is the floor, nothing else", function()
        local o = { band = { 0, 0.01 }, iv = { 0.21, 0.21 }, est = 0.21, truth = 0.004, before = 1 }
        assert.are.same({ 1, 1, 0, 0, 0, 0, 1, 1 }, check(o))
        o.est, o.iv = 0.02, { 0, 0.02 }
        assert.are.same({ 1, 1, 0, 0, 0, 1, 0, 0 }, check(o))
    end)

    it("a run's first applied band is checked", function()
        local o = { band = { 0.6, 0.61 }, est = 0.605, truth = 0.605, used = 1 }
        assert.are.same({ 1, 1, 0, 0, 0, 0, 0, 0 }, check(o))
    end)
end)
