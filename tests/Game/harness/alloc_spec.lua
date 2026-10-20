-- tests/Game/harness/alloc_spec.lua (harness design §3.6): one generated party fight (two other sources on our
-- target, two mobs on us of different strength, the second joining: amount bands; our presses and usability answered
-- from our true power: the oracle's verdicts, a retraction and a veto among them) replayed through VirtualState:
-- after a warm-up, the replays allocate nothing.
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")
local alloc = require("Game.State.helpers.alloc")

describe("the harness drive", function()
    it("allocates nothing in VirtualState replaying a generated party fight", function()
        local o = scenarios.oracle({
            duration = 60,
            others = { "melee", "caster" },
            attackers = 2,
            joinAt = { [2] = 10 },
            mobs = { { damage = { 10, 14 }, period = 2.0 }, { damage = { 20, 28 }, period = 2.6 } },
        })
        local s = scenarios.stream(o, 7) -- a seed whose fight retracts, vetoes and bands (seed 4 no longer retracts)
        local c = drive.boot({ max = 100 })
        local ok, bytes = pcall(alloc.bytes, function(i)
            drive.run(c, s, i * 100)
        end, 5)
        drive.restore(c)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
        local L = c.I.Log
        assert.is_true(
            L.oracle.retracted > 0 and L.oracle.vetoed > 0 and L.onus.byBand > 0,
            ("every path exercised: retracted %d vetoed %d byBand %d"):format(
                L.oracle.retracted,
                L.oracle.vetoed,
                L.onus.byBand
            )
        )
    end)
end)
