-- tests/Game/harness/drive_spec.lua (unit-registry plan, Task 10b): the drive's per-row ticket captures (payAt,
-- payKind) through I.Tickets.onPay, on a scenario's stream.
local drive = require("Game.harness.drive")
local scenarios = require("Game.harness.scenarios")
local fs = require("Game.State.helpers.fake_spec")

describe("the drive's ticket captures", function()
    it("records the paid swing ticket's anchor and kind on a white wound's row", function()
        local s = scenarios.stream({ duration = 10 }, 3)
        local c = drive.boot()
        drive.run(c, s)
        drive.restore(c)
        local X, n = c.I.Expect, 0
        for i = 1, s.n do
            if c.crHand[i] > 0 and c.payKind[i] == X.MELEE then
                n = n + 1
                assert.are.equal(c.crAt[i], c.payAt[i]) -- the credited swing is the ticket's anchor
            end
        end
        assert.is_true(n > 0)
    end)

    it("lands a bolt at its success + distance / 20 and pays a FLIGHT ticket anchored at that success", function()
        local s = scenarios.stream({ duration = 6, noMelee = true, spells = { { 2, "bolt" } }, distance = 30 }, 3)
        local c = drive.boot({
            boot = function(c)
                c.ctl.ranges[fs.SPENDER_P] = { 0, 30 } -- the bolt's max range sets its flight window (default 5: melee)
                c.I.Build(fs.def(fs.new(9, nil, nil, true)), 0.1)
                c.VS.Start(c.api)
            end,
        })
        drive.run(c, s)
        drive.restore(c)
        local success, row
        for i = 1, s.n do
            if s.ev[i] == "UNIT_SPELLCAST_SUCCEEDED" and s.a1[i] == "player" and s.a3[i] == fs.SPENDER_P then
                success = s.t[i]
            elseif s.ev[i] == "UNIT_COMBAT" and s.a1[i] == "target" and s.a5[i] == 8 then
                row = i
            end
        end
        assert.is_truthy(success and row)
        assert.is_true(math.abs(s.t[row] - (success + 30 / 20)) < 1e-6, "landed at " .. s.t[row] - success)
        assert.are.equal(c.I.Expect.FLIGHT, c.payKind[row])
        assert.are.equal(success, c.payAt[row])
    end)
end)
