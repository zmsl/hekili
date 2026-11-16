-- tests/Game/harness/percent_cost_round_spec.lua (CN22): a percent-of-base cost is the nearest whole mana, a half
-- rounding up (wowsims e4ef929e54 sim/core/mana.go `math.Round(BaseCostPercent * BaseMana / 100)`, from the game's
-- form costs: 35% of base 914 costs 320, not 319), in both layers alike: the simulation's ns.FractionCost and the
-- belief's I.BaseCostOf; and the base the belief learns back from a cost read prices that read again.
local headless = require("Game.harness.headless")
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

-- Fractions as num / den: whole percents below 100 (a cost of 1 is flat), halves, the decimals the packs declare (5.81,
-- 13.9) and ties at both ends.
local PCTS = { { 1, 200 }, { 1, 40 }, { 1, 8 }, { 581, 10000 }, { 1390, 10000 }, { 3, 8 }, { 5, 8 } }
for p = 1, 100 - 1 do -- not 100: a cost of 1 is flat (written so, as 99 is a content ID to the boundary spec)
    PCTS[#PCTS + 1] = { p, 100 }
end

describe("a percent-of-base cost rounds to the nearest whole, in both layers", function()
    local FractionCost, I, VS, ctl

    setup(function()
        FractionCost = headless.new().ns.FractionCost
    end)

    before_each(function()
        local api
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        local h = fs.new(9)
        h.Class.abilities.spender_c.spend = 0.5
        local def = fs.def(h)
        def.resources[1].base = 200
        I.Build(def, 1)
        VS.Start(api)
        ctl.Tick(1)
    end)

    it("prices every percent of base 900-1800 at the half-up nearest whole, belief and simulation", function()
        local obj, res, bad = I.ab.obj[3], {}, 0
        for b = 900, 1800 do
            I.basePow[1], res.base = b, b
            for _, q in ipairs(PCTS) do
                local c = q[1] / q[2]
                local want = math.floor((2 * q[1] * b + q[2]) / (2 * q[2])) -- exact: whole numbers below 2^53
                obj.spend = c
                local belief, sim = I.BaseCostOf(3), FractionCost(c, res)
                if belief ~= want or sim ~= want then
                    bad = bad + 1
                    assert.are.same({ want, want }, { belief, sim }, ("%d x %d / %d"):format(b, q[1], q[2]))
                end
            end
        end
        assert.are.equal(0, bad)
    end)

    it("rounds a tie up: 50% of 1213 is 607, 35% of 914 is 320", function()
        I.basePow[1] = 1213
        I.ab.obj[3].spend = 0.5
        assert.are.same({ 607, 607 }, { I.BaseCostOf(3), FractionCost(0.5, { base = 1213 }) })
        I.basePow[1] = 914
        I.ab.obj[3].spend = 0.35
        assert.are.same({ 320, 320 }, { I.BaseCostOf(3), FractionCost(0.35, { base = 914 }) })
    end)

    it("learns back from a cost read the base nearest read / fraction, which prices the read again", function()
        -- the game's form cost: 35% at base 914 reads 320 (wowsims's evidence); 320 / 0.35 = 914.3
        local h = fs.new(9)
        h.Class.abilities.spender_c.spend = 0.35
        local def = fs.def(h)
        def.resources[1].base = 200 -- the pack's fallback, which misprices the read
        I.Build(def, 1)
        ctl.known[fs.SPENDER_C] = true
        ctl.costs[fs.SPENDER_C] = { { type = 1, cost = 320 } }
        ctl.Fire("SPELLS_CHANGED")
        assert.are.same({ 914, 320 }, { VS.BasePower(fs.RAGE), I.CostOf(3) })
        -- every true base and fraction: the learned base reprices its read; the read pins f x base to within a half,
        -- so the base to within 0.5 / f, and the learned base, read / f rounded, to within 0.5 more
        for _, f in ipairs({ 0.055, 0.08, 0.11, 0.35, 0.55 }) do
            h.Class.abilities.spender_c.spend = f
            for b = 900, 1800, 37 do
                I.Build(def, 1)
                ctl.known[fs.SPENDER_C] = true
                local read = math.floor(f * b + 0.5 + 1e-6)
                ctl.costs[fs.SPENDER_C] = { { type = 1, cost = read } }
                ctl.Fire("SPELLS_CHANGED")
                local learned = VS.BasePower(fs.RAGE)
                local why = ("%g x %d reads %d, learned %d"):format(f, b, read, learned)
                assert.are.equal(read, I.CostOf(3), why)
                assert.is_true(math.abs(learned - b) <= 0.5 / f + 0.5 + 1e-9, why)
            end
        end
    end)
end)
