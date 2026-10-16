-- tests/Virtual/harness/alloc_spec.lua (harness design §3.6): one generated party fight (two other sources on our
-- target, a mob on us, our presses) replayed through VirtualState: after a warm-up, the replays allocate nothing.
local scenarios = require("Virtual.harness.scenarios")
local drive = require("Virtual.harness.drive")
local alloc = require("Virtual.State.helpers.alloc")

describe("the harness drive", function()
    it("allocates nothing in VirtualState replaying a generated party fight", function()
        local s = scenarios.stream(scenarios.oracle({ duration = 30, others = { "melee", "caster" } }), 2)
        local c = drive.boot({ max = 100 })
        local ok, bytes = pcall(alloc.bytes, function(i)
            drive.run(c, s, i * 100)
        end, 5)
        drive.restore(c)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
    end)
end)
