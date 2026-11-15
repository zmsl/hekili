-- tests/Forever/warrior_world_spec.lua: the Warrior loop world's rage from its own presses follows the character's
-- talent ranks, as the class file and wowsims do (bloodrage.go: Improved Bloodrage x1.25 a rank on the instant rage and
-- each tick; berserker_rage.go: Improved Berserker Rage 5 a rank).
local headless = require("Game.harness.headless")
local gate = require("Forever.helpers.fury_gate")

describe(
    "the Warrior world's rage from a press (the Fury build: Improved Bloodrage 1, Improved Berserker Rage 2)",
    function()
        local C, H, W, e, gains, at

        before_each(function()
            C = gate.content(60)
            H = headless.new({ character = C.character(), pack = C.PACK })
            gains, at = {}, {}
            e = { auras = {}, power = 0 }
            W = { t = 0 }
            function W.gain(_, n)
                gains[#gains + 1] = n
            end
            function W.at(when, f)
                at[#at + 1] = when
                f()
            end
            function W.applyAura() end
        end)

        it("pays Bloodrage's 10 x 1.25 at once and 1 x 1.25 at each of its ten ticks", function()
            C.resolve("bloodrage", H).effect(W, e)
            assert.are.same({ 12.5, 1.25, 1.25, 1.25, 1.25, 1.25, 1.25, 1.25, 1.25, 1.25, 1.25 }, gains)
            assert.are.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, at)
        end)

        it("pays Berserker Rage's 5 a rank of Improved Berserker Rage", function()
            C.resolve("berserker_rage", H).effect(W, e)
            assert.are.same({ 10 }, gains)
        end)
    end
)
