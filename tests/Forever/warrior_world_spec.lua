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

        -- wowsims talents_fury.go at ab0f00e4fc (EV-0148, EV-0138; aura_helpers.go:163 rolls it): a landed Heroic
        -- Strike or Cleave rolls Unbridled Wrath (11.9% a rank, 1 rage a proc) and spends one Reckless Swings charge for
        -- 5; an avoided one neither. The roll is stubbed: `procs` answers each draw, `asked` keeps its chance.
        it(
            "pays a landed strike's Unbridled Wrath roll and one Reckless Swings charge, an avoided one's nothing",
            function()
                local ww = require("Forever.helpers.warrior_world")
                local procs, asked = {}, {}
                ww.wrng = {
                    chance = function(p)
                        asked[#asked + 1] = p
                        return table.remove(procs, 1)
                    end,
                }
                for _, key in ipairs({ "heroic_strike", "cleave" }) do
                    local us = { auras = {}, power = 0 }
                    ww.charges, ww.chargesE = 3, us
                    gains, asked = {}, {}
                    C.resolve(key, H).effect(W, us)
                    us.struck(W, "DODGE")
                    assert.are.same({}, gains)
                    assert.are.same({}, asked) -- an avoided strike rolls nothing
                    procs = { true, false, true, false }
                    us.struck(W, "WOUND") -- a proc and a charge
                    us.struck(W, "WOUND") -- no proc, a charge
                    assert.are.equal(1, ww.charges)
                    ww.charges = 0
                    us.struck(W, "WOUND") -- a proc, no charge
                    us.struck(W, "WOUND") -- neither: no gain
                    assert.are.same({ 6, 5, 1 }, gains, key)
                    assert.are.equal(4, #asked)
                    assert.is_near(0.595, asked[1], 1e-9)
                end
                -- and a landed white swing its roll: 3.46 x 2.1 main hand, + 1 on a proc
                local c = C.character()
                procs = { true, false }
                assert.is_near(3.46 * 2.1 + 1, C.gain(1, 1, 100, "", c), 1e-9)
                assert.is_near(3.46 * 2.1, C.gain(1, 1, 100, "", c), 1e-9)
                -- a two-hander's swing (the Arms world) 1 rage a proc too (owner L1419, wowsims ab0f EnergizeEffect 10 tenths)
                procs = { true }
                assert.is_near(4.5 * 3.6 + 1, ww.gain(1, 1, 100, "", c), 1e-9)
                -- no rank, no draw (the Arms build; kill_rows' rage hook passes no character)
                asked = {}
                assert.is_near(4.5 * 3.6, ww.gain(1, 1, 100, "", nil), 1e-9)
                assert.is_near(3.46 * 2.1, C.gain(1, 1, 100, "", { talents = {} }), 1e-9)
                assert.are.same({}, asked)
                ww.wrng = nil
            end
        )

        -- the roll draws from the world's own stream (its pull hands it over): the rate over many swings is the
        -- chance, and its draws leave every other stream of the world where it was
        it("rolls Unbridled Wrath from a stream of its own at about its chance", function()
            local ww = require("Forever.helpers.warrior_world")
            local world = require("Game.harness.world")
            local A, B = world.new(7), world.new(7)
            ww.WORLD.script(A)
            local c, n, procs = C.character(), 20000, 0
            for _ = 1, n do
                local d = C.gain(1, 1, 100, "", c) - 3.46 * 2.1
                assert.is_true(math.abs(d) < 1e-9 or math.abs(d - 1) < 1e-9, tostring(d)) -- 0 or 1, never a share
                procs = procs + d
            end
            assert.is_near(0.595, procs / n, 0.015)
            for _, k in ipairs({ "rng", "crng", "grng", "mrng", "prng" }) do
                assert.are.equal(B[k].next(), A[k].next(), k)
            end
            assert.are_not.equal(B.krng.next(), B.rng.next())
            ww.wrng = nil
        end)
    end
)
