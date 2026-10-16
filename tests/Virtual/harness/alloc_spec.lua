-- tests/Virtual/harness/alloc_spec.lua (harness design §3.6): one generated party fight (two other sources on our
-- target, a mob on us, our presses, usability answered from our true power: the oracle's verdicts, a retraction and a
-- rescue among them) replayed through VirtualState: after a warm-up, the replays allocate nothing.
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
        local o = c.I.Log.oracle
        assert.is_true(o.retracted > 0 and o.rescued > 0, "the fight exercises a retraction and a rescue")
    end)
end)
