-- tests/Forever/loop_warlock_cycle_spec.lua (option D, owner 2026-11-11): Recommend Target Swaps in a three-mob world
-- (ab.lua's cycle-follow arm: the two extra mobs with plates, the enemy plates shown), the driver following the cycle
-- icon (loop.lua followCycle). Destruction's multi-target list spreads its curse and DoTs through `cycle_targets=1`:
-- the swaps happen, the spread DoT reaches every mob, and the icons stay as steady as in the toggle-off twin
-- (cycle-follow-off; the owner's no-jitter rule: flicker per minute at most 1.10 times the twin's).
local loop = require("Game.harness.loop")
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.warlock_world")

describe("Recommend Target Swaps in a three-mob world #warlock", function()
    it("Destruction swaps to spread its DoTs and curse to the other mobs, as steady as with the toggle off", function()
        local L = loop.new(w.Destruction)
        local a = loop.fight(L, 1, { arm = "cycle-follow" })
        local mOn = loop.tally(loop.new(w.Destruction), 3, { arm = "cycle-follow" })
        local on = loop.summary(mOn)
        pack_gate.health(mOn, on, loop.line(mOn)) -- the toggle-on path: no error, raise, self-check miss or secret
        local off = loop.summary(loop.tally(loop.new(w.Destruction), 3, { arm = "cycle-follow-off" }))
        print(
            ("\ncycle-follow Destruction: cycle presses %d, landed on another mob %d; flicker %.2f/min (off %.2f)"):format(
                a.cyclePresses,
                a.cycleLanded,
                on.flicker,
                off.flicker
            )
        )
        assert.is_true(a.cyclePresses > 0)
        assert.are.equal(2, a.cycleMobs, "the spread reached both other mobs") -- each truly carries a swapped debuff
        assert.is_true(on.flicker <= 1.10 * off.flicker + 1e-9, "flicker on " .. on.flicker .. " off " .. off.flicker)
    end)
end)
