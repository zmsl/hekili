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

        -- wowsims execute.go at e4ef929e54 (7025f28b98): the extra rage goes into a landed strike only; an avoided one
        -- keeps it and gives none of the base cost back
        it("spends Execute's extra rage on a landed strike only, and refunds none of an avoided one's cost", function()
            local p = C.resolve("execute", H)
            assert.are.equal(0, p.refund or 0)
            e.power, e.target = 40, {}
            local amounts = {}
            function W.hit(_, _, amount)
                amounts[#amounts + 1] = amount
                return { act = "DODGE" }
            end
            p.effect(W, e)
            assert.are.same({}, gains)
            function W.hit(_, _, amount)
                amounts[#amounts + 1] = amount
                return { act = "WOUND" }
            end
            p.effect(W, e)
            assert.are.same({ -40 }, gains)
            assert.are.same({ 600 + 15 * 40, 600 + 15 * 40 }, amounts)
        end)

        -- wowsims talents_fury.go at ab0f00e4fc (EV-0148, EV-0138): a landed Heroic Strike or Cleave rolls Unbridled
        -- Wrath (5/5: 0.595 expected) and spends one Reckless Swings charge for 5; an avoided one neither
        it("pays a landed strike's Unbridled Wrath and one Reckless Swings charge, an avoided one's nothing", function()
            local ww = require("Forever.helpers.warrior_world")
            for _, key in ipairs({ "heroic_strike", "cleave" }) do
                local us = { auras = {}, power = 0 }
                ww.charges, ww.chargesE = 2, us
                gains = {}
                C.resolve(key, H).effect(W, us)
                us.struck(W, "DODGE")
                assert.are.same({}, gains)
                us.struck(W, "WOUND")
                assert.are.equal(1, #gains)
                assert.is_true(math.abs(gains[1] - 5.595) < 1e-9, key .. " " .. tostring(gains[1]))
                assert.are.equal(1, ww.charges)
                ww.charges = 0
                us.struck(W, "WOUND")
                assert.is_true(math.abs(gains[2] - 0.595) < 1e-9, key .. " " .. tostring(gains[2]))
            end
            -- and a landed white swing its Unbridled Wrath: 3.46 x 2.1 main hand at 5/5
            local c = C.character()
            assert.is_true(math.abs(C.gain(1, 1, 100, "", c) - (3.46 * 2.1 + 0.595)) < 1e-9)
        end)
    end
)
