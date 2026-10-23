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
        -- the paths the default arm's fight takes (a provider arm's answers take others: recorded, providers §4.1)
        require("Game.harness.ab").check(
            L.oracle.retracted > 0 and L.oracle.vetoed > 0 and L.onus.byBand > 0,
            "harness alloc",
            ("every path exercised: retracted %d vetoed %d byBand %d"):format(
                L.oracle.retracted,
                L.oracle.vetoed,
                L.onus.byBand
            )
        )
    end)

    it("allocates nothing in VirtualState replaying a solo 300 s fight of every spell kind", function()
        local detect = require("Game.harness.detect")
        local spells = {}
        for t = 2, 298, 2 do
            spells[#spells + 1] = { t, ({ "instant", "bolt", "doti", "ticks", "unmapped" })[(t / 2) % 5 + 1] }
        end
        local s = scenarios.stream({ duration = 300, spells = spells, distance = 25 }, 11)
        local c = drive.boot({ boot = detect.boot })
        local ok, bytes = pcall(alloc.bytes, function(i)
            drive.run(c, s, i * 400)
        end, 2)
        local opened = c.I.Tickets.opened
        drive.restore(c)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
        assert.is_true(opened > 0, "the fight opened no ticket")
    end)
end)
