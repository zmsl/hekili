-- tests/Forever/druid_loop_world_spec.lua: the Druid loop world rolls Primal Fury's rage ("Blood Frenzy" on Forever,
-- 16958) on a crit of ours in Bear Form, as wowsims e4ef929e54 does (talents_feral_combat.go: 16959's 5 rage at rank / 2),
-- from its own stream, so the belief's no-optimistic-proc rule (owner L1397) is scored against a roll (Fable L1984).
local headless = require("Game.harness.headless")
local world = require("Game.harness.world")
local w = require("Forever.helpers.druid_loop_world")

local RAGE, BEAR = 1, w.FORM.bear_form

describe("the Druid world's Primal Fury roll", function()
    local W, gains, procs, asked

    -- the content booted (its class data read by a press) with stubbed rolls: `procs` answers each draw, `asked` keeps
    -- its chance
    local function boot(C, key)
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local p = C.resolve(key, H)
        local rng = {
            chance = function(c)
                asked[#asked + 1] = c
                return table.remove(procs, 1)
            end,
        }
        W = {
            t = 0,
            krng = rng,
            rng = {
                chance = function()
                    return false
                end,
            },
        }
        function W.gain(_, n)
            gains[#gains + 1] = n
        end
        function W.hit()
            return { act = "WOUND", flag = "CRITICAL" }
        end
        local us = { auras = {}, power = 0, form = BEAR }
        C.WORLD.script(W, us)
        return p, us
    end

    before_each(function()
        gains, procs, asked = {}, {}, {}
    end)
    after_each(function()
        w.pfRng = nil
    end)

    it("rolls 5 rage at 50% on a bear crit at 1/2 (Guardian): a strike, Maul's swing and a white crit", function()
        local C = w.Guardian
        assert.are.equal(1, C.character().talents[16958])
        local p, us = boot(C, "primal_bite")
        local white = C.gain(RAGE, 1, 0, "") -- a white hit: no roll
        assert.are.same({}, asked)
        procs = { true, false }
        p.effect(W, us)
        p.effect(W, us)
        assert.are.same({ 5 }, gains) -- one proc, one none: never the 2.5 mean
        procs = { false, true }
        us.struck(W, "WOUND", "CRITICAL")
        us.struck(W, "WOUND", "CRITICAL")
        us.struck(W, "DODGE", "") -- an avoided Maul rolls nothing
        assert.are.same({ 5, 5 }, gains)
        procs = { true, false }
        local crit = C.gain(RAGE, 1, 0, "CRITICAL")
        assert.are.equal(crit, C.gain(RAGE, 1, 0, "CRITICAL") + 5)
        assert.is_true(crit > 2 * white) -- a crit's doubled swing under the proc
        assert.are.same({ 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 }, asked)
    end)

    it("pays 5 on every bear crit at 2/2 (Feral) without a draw", function()
        local C = w.Feral
        assert.are.equal(2, C.character().talents[16958])
        local p, us = boot(C, "maul")
        us.struck(W, "WOUND", "CRITICAL")
        assert.are.same({ 5 }, gains)
        assert.are.equal(C.gain(RAGE, 1, 0, "") * 2 + 5, C.gain(RAGE, 1, 0, "CRITICAL"))
        assert.are.same({}, asked)
        assert.is_truthy(p)
    end)

    -- the roll draws from the world's own stream (its pull hands it over): the rate over many crits is the chance, and
    -- its draws leave every other stream of the world where it was
    it("rolls from a stream of its own at about its chance", function()
        local C = w.Guardian
        boot(C, "primal_bite")
        local A, B = world.new(7), world.new(7)
        C.WORLD.script(A, { auras = {}, form = BEAR })
        local base, n, procsN = C.gain(RAGE, 1, 0, "") * 2, 20000, 0
        for _ = 1, n do
            local d = C.gain(RAGE, 1, 0, "CRITICAL") - base
            assert.is_true(math.abs(d) < 1e-9 or math.abs(d - 5) < 1e-9, tostring(d)) -- 0 or 5, never a share
            procsN = procsN + d / 5
        end
        assert.is_near(0.5, procsN / n, 0.015)
        for _, k in ipairs({ "rng", "crng", "grng", "mrng", "prng" }) do
            assert.are.equal(B[k].next(), A[k].next(), k)
        end
        assert.are_not.equal(B.krng.next(), B.rng.next())
    end)
end)
