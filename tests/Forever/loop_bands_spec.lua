-- tests/Forever/loop_bands_spec.lua (LibHiddenValues integration design 5.4, 6.1 lane B1): the `bands` arm, record-only.
-- The driver's belief watches through fake_lhv.lua (loop.lua), the observer pushing the world's truth; no family reads
-- the bands yet, so every output of a fight equals the default arm's on the same seed, and each live band the belief
-- logged holds the truth at its own stamp (loop.bandCheck: containment 100%), on each channel the world has.
local loop = require("Game.harness.loop")
local ab = require("Game.harness.ab")
local ww = require("Forever.helpers.warrior_world")
local dlw = require("Forever.helpers.druid_loop_world")
local mw = require("Forever.helpers.mage_world")

-- The outputs the gates read from a run (loop.run's record), and the bands arm's lines.
local ROWS = { "ours", "pressed", "presses", "pressedBy", "refused", "gap", "readyShort", "heldReady", "loOver", "up" }

local function fight(content, arm, seed)
    local L, lines, check = loop.new(content), {}, ab.check
    ab.check = function(ok, label, line) -- the lines a record-only arm writes to .ab/<arm>.tsv
        lines[#lines + 1] = label .. " " .. tostring(line)
        return check(ok, label, line, "default")
    end
    local ok, run = pcall(loop.run, L, seed, { duration = 30, arm = arm }, { { H = L.us } })
    ab.check = check
    assert(ok, run)
    assert.are.same({ 0, 0 }, { run.errors, run.raises })
    return run, L.us, lines
end

describe("the bands arm (record-only) #slow", function()
    for _, case in ipairs({
        { "Arms (rage)", ww, { -1, 0, 1 } },
        { "Feral (energy; mana and rage while not shown are paused)", dlw.Feral, { -1, 0 } },
        { "Frost (mana)", mw.Frost, { -1, 0 } },
    }) do
        it(case[1] .. ": the rows equal the default arm's; every live band holds the truth at its stamp", function()
            local base = fight(case[2], "default", 3)
            local run, H, lines = fight(case[2], "bands", 3)
            for _, key in ipairs(ROWS) do
                assert.are.same(base[key], run[key], key)
            end
            local b = run.bands
            assert.are.same({}, b.misses)
            assert.are.equal(b.checked, b.held)
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
            assert.is_truthy(lines[#lines]:match("^bands seed 3 checked %d+ held %d+ lagged %d+ live "), lines[#lines])
        end)
    end

    -- The gate's path (loop.tally): three fights on one boot, run A with the oracle shadow, run B, the 30 s gap between
    -- fights (the idle pause), the fake and its history carried into each new world, a kill's gone, the next prime.
    it("three fights on one boot: the tally the default's, every fight's bands holding the truth", function()
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
        local base = tally("default")
        local m, lines = tally("bands")
        for _, key in ipairs({ "fights", "both", "agree", "conf", "react", "refused", "attempts", "episodes" }) do
            assert.are.same(base[key], m[key], key)
        end
        for _, key in ipairs({ "readyShort", "heldReady", "loOver", "A", "B", "gap", "selfCheck", "pressedBy" }) do
            assert.are.same(base[key], m[key], key)
        end
        assert.are.equal(3, #lines) -- run A's driver only: never the oracle, never run B
        for f, line in ipairs(lines) do
            local checked, held = line:match("checked (%d+) held (%d+)")
            assert.are.equal(checked, held, line)
            for _, ch in ipairs({ "-1", "0", "1" }) do
                local n = tonumber(line:match("[ ,]" .. ch .. ":(%d+)"))
                assert.is_true((n or 0) > 100, f .. ": " .. line)
            end
        end
    end)

    it("bands-drop: the capability lost mid-fight, the rows still the default's, no band logged after it", function()
        local base = fight(ww, "default", 5)
        local run, H = fight(ww, "bands-drop", 5)
        for _, key in ipairs(ROWS) do
            assert.are.same(base[key], run[key], key)
        end
        local I = H.ns.VirtualStateInternal
        for _, live in pairs(I.bandLive) do
            assert.is_false(live)
        end
        assert.are.equal(run.bands.checked, run.bands.held)
        assert.is_true(run.bands.checked > 0)
    end)
end)
