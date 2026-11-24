-- tests/Forever/loop_ttd_spec.lua (lane B8, design 2.7's jitter rule): the `ttd` arm, record-only. The real
-- LibTimeToDie runs in the driving instance over the bands arms' fake LibHiddenValues (ttd_rig.lua); the core's
-- fight_remains answers its live estimate, and each fight writes a `ttd` row (loop.ttdRow) with the error against the
-- kill. The flicker comparison with the bands arm is the A/B's (make gate-ab-body AB_ARMS="bands ttd").
local loop = require("Game.harness.loop")
local ab = require("Game.harness.ab")
local ww = require("Forever.helpers.warrior_world")

local function fight(content, arm, seed)
    local L, lines, check = loop.new(content), {}, ab.check
    ab.check = function(ok, label, line) -- the lines a record-only arm writes to .ab/<arm>.tsv
        lines[#lines + 1] = label .. " " .. tostring(line)
        return check(ok, label, line, "default")
    end
    local ok, run = pcall(loop.run, L, seed, { duration = 240, arm = arm }, { { H = L.us } })
    ab.check = check
    assert(ok, run)
    assert.are.same({ 0, 0 }, { run.errors, run.raises })
    return run, L.us, lines
end

describe("the ttd arm (record-only) #slow", function()
    it("Arms: the library goes live, fight_remains answers it, the row scores it against the kill", function()
        local run, H, lines = fight(ww, "ttd", 3)
        local row
        for _, l in ipairs(lines) do
            row = l:match("^ttd .- (seed .*)$") or row
        end
        assert.is_string(row, table.concat(lines, "\n"))
        local polls, live, scored = row:match("polls (%d+) live (%d+) scored (%d+)")
        polls, live, scored = tonumber(polls), tonumber(live), tonumber(scored)
        assert.is_true(polls > 0 and live > 0, row)
        assert.is_true(scored > 0, row) -- a kill in the fight: the error is known
        assert.is_truthy(H.Hekili:GetTTDInfo():match("^time to die: "), H.Hekili:GetTTDInfo())
        assert.are.equal(run.ttd.polls, polls)
    end)

    -- (L1814) the arm measures what our estimate costs, not the oracle's blindness: the plain oracle answers the true
    -- time left (fix1_helper's truth override), our driver keeps the library's estimate
    it("the plain oracle answers the true time left from the calibrated rate; ours keeps the library", function()
        local seeds, check, record = loop.TRUTH_SEEDS, ab.check, ab.record
        finally(function()
            loop.TRUTH_SEEDS, ab.check, ab.record = seeds, check, record
        end)
        ab.check = function(ok, label, line) -- the record-only rows (the ttd row) judged as the default's
            return check(ok, label, line, "default")
        end
        ab.record = function() end
        loop.TRUTH_SEEDS = 1 -- one calibration fight: the rate's arithmetic, not its accuracy
        local L = loop.new(ww)
        local ours, oracle = L.us.Hekili.GetGreatestTTD, L.oracle.Hekili.GetGreatestTTD
        local o = { duration = 60, arm = "ttd" }
        local rate = loop.truthRate(L.content, o)
        assert.is_true(rate.A > 0 and rate.B > 0)
        assert.are.equal(rate, loop.truthRate(L.content, o)) -- one calibration a world
        assert.is_nil(loop.truthRate(L.content, { duration = 60, mobHealth = 1e9 })) -- no kill: no truth to tell
        local party = loop.truthRate(L.content, { duration = 60, arm = "ttd", others = { "melee", "caster" } })
        assert.is_true(party.A > rate.A) -- a party's damage on the target is the world's rate too
        local seen = {}
        o.on = function(run, steps, t)
            if t >= loop.PULL + 5 and not seen.oracle and steps[2] then
                local mob
                for _, e in ipairs(run.W.ents) do
                    mob = mob or (e.kind == "mob" and e) or nil
                end
                seen.oracle = steps[2].H.Hekili:GetGreatestTTD()
                seen.want = math.min(mob.health / rate.A, run.W.stopAt - run.W.t)
                seen.ours = steps[1].H.Hekili.GetGreatestTTD
            end
        end
        loop.tally(L, 1, o)
        assert.is_number(seen.oracle)
        assert.is_true(seen.oracle < 3600, seen.oracle)
        assert.is_near(seen.want, seen.oracle, 1e-6)
        assert.are.equal(ours, seen.ours) -- plain side only
        assert.are.equal(oracle, L.oracle.Hekili.GetGreatestTTD) -- restored after the run
    end)
end)
