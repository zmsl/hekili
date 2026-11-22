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
end)
