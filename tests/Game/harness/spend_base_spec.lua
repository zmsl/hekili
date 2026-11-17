-- tests/Game/harness/spend_base_spec.lua (central fix 22, gap BB): an ability declaring `spendBase = true` prices its
-- `spend`, scalar or function, as a fraction of its pool's base power at any magnitude (c x base to the nearest whole,
-- a half up: percent_cost_round_spec.lua); without the
-- flag a cost between 0 and 1 is still a fraction and any other cost is points (Engine/Sim/State.lua ns.SpendPoints).
local headless = require("Game.harness.headless")

describe("the sim's percent-of-base cost (spendBase)", function()
    local H, S, class, basePower
    local BASE = 1213

    setup(function()
        H = headless.new()
        S = H.Hekili.State
        class = H.Hekili.Class
        local spec = class.specs[0]
        spec:RegisterResource(H.env.Enum.PowerType.Mana)
        rawset(S, "mana", spec.resources.mana.state)
        local defs = {
            base_scalar = { id = -9101, spend = 1.4, spendType = "mana", spendBase = true },
            base_fn = {
                id = -9102,
                spend = function()
                    return 0.4 * 3.5 -- 1.4 of base, from a function
                end,
                spendType = "mana",
                spendBase = true,
            },
            half = { id = -9103, spend = 0.5, spendType = "mana" },
            flat = { id = -9104, spend = 40, spendType = "mana" },
        }
        for k, d in pairs(defs) do
            spec:RegisterAbility(k, d)
            class.abilities[k] = spec.abilities[k]
        end
        basePower = H.ns.VirtualState.BasePower
        H.ns.VirtualState.BasePower = function()
            return BASE + 7 -- not the sim's source any more: the reset's UnitPowerMax read is (border batch 2)
        end
        S.mana.base = BASE -- as the reset stores UnitPowerMax's second value
    end)

    teardown(function()
        H.ns.VirtualState.BasePower = basePower
    end)

    it("prices a declared fraction of 1.4, scalar or function, at 1.4 x base to the nearest whole", function()
        local want = 1698 -- 1698.2
        assert.are.same({ want, want }, { S.action.base_scalar.cost, S.action.base_fn.cost })
        assert.are.same({ want, want }, { H.ns.SpendPoints(1.4, S.mana, class.abilities.base_fn), want })
    end)

    it("keeps a 0.5 cost without the flag a fraction and a 40 cost flat", function()
        assert.are.same({ 607, 40 }, { S.action.half.cost, S.action.flat.cost }) -- 606.5: a half rounds up
    end)

    -- wowsims e4ef929e54 prices a percent-of-base cost whole first (mana.go:372 newManaCost, math.Round) and then
    -- multiplies it by the cost modifiers, unrounded (spell.go:1055 ApplyCostModifiers): 11% of 1720 is 189, a halving
    -- modifier makes it 94.5 (not 0.055 x 1720 = 94.6 priced whole) and a 12% cut 166.32 (not 0.0968 x 1720 = 166.5).
    it("prices a fraction whole first, then cuts it by the cost modifiers in scope, unrounded", function()
        local spec = class.specs[0]
        spec:RegisterAbility("pct_spender", { id = -9105, spend = 0.11, spendType = "mana" })
        class.abilities.pct_spender = spec.abilities.pct_spender
        spec:RegisterCostMod({ aura = "cut_half", pct = -0.5, spells = { -9105 } })
        spec:RegisterCostMod({ aura = "cut_some", pct = -0.12, spells = { -9105 } })
        local buff, up = rawget(S, "buff"), {}
        rawset(
            S,
            "buff",
            setmetatable(up, {
                __index = function()
                    return { up = false }
                end,
            })
        )
        S.mana.base = 1720
        local a = class.abilities.pct_spender
        local got = { H.ns.SpendPoints(0.11, S.mana, a) }
        up.cut_half = { up = true }
        got[2] = H.ns.SpendPoints(a.spend, S.mana, a)
        up.cut_half, up.cut_some = nil, { up = true }
        got[3] = H.ns.SpendPoints(a.spend, S.mana, a)
        rawset(S, "buff", buff)
        S.mana.base = BASE
        assert.are.same({ 189, 94.5 }, { got[1], got[2] })
        assert.is_true(math.abs(got[3] - 166.32) < 1e-9, tostring(got[3]))
    end)

    -- A test-only talent-gated modifier (no aura), its `pct` by rank: a passive talent's cut on the whole price, as
    -- wowsims e4ef929e54 applies one (spell_mod.go:909): 11% of 1720 is 189, a 12% rank 166.32.
    it("cuts a fraction's whole price by a talent's rank, with no aura", function()
        local spec = class.specs[0]
        spec:RegisterAbility("pct_talented", { id = -9106, spend = 0.11, spendType = "mana" })
        class.abilities.pct_talented = spec.abilities.pct_talented
        spec:RegisterCostMod({ talent = "cut_rank", pct = { -0.04, -0.08, -0.12 }, spells = { -9106 } })
        S.mana.base = 1720
        local a, got, buff = class.abilities.pct_talented, {}, rawget(S, "buff")
        rawset(
            S,
            "buff",
            setmetatable({}, { -- the earlier test's modifiers' auras, never registered: down
                __index = function()
                    return { up = false }
                end,
            })
        )
        rawset(S.talent, "cut_rank", { rank = 3 })
        got[1] = H.ns.SpendPoints(a.spend, S.mana, a)
        rawset(S.talent, "cut_rank", { rank = 0 })
        got[2] = H.ns.SpendPoints(a.spend, S.mana, a)
        rawset(S.talent, "cut_rank", nil)
        rawset(S, "buff", buff)
        S.mana.base = BASE
        assert.is_true(math.abs(got[1] - 166.32) < 1e-9, tostring(got[1]))
        assert.are.equal(189, got[2])
        assert.are.same({}, H.errors)
    end)
end)
