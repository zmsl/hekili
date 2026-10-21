-- tests/Game/harness/spend_base_spec.lua (central fix 22, gap BB): an ability declaring `spendBase = true` prices its
-- `spend`, scalar or function, as a fraction of its pool's base power at any magnitude (floor(c x base)); without the
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
            return BASE
        end
    end)

    teardown(function()
        H.ns.VirtualState.BasePower = basePower
    end)

    it("prices a declared fraction of 1.4, scalar or function, at floor(1.4 x base)", function()
        local want = math.floor(1.4 * BASE + 1e-6)
        assert.are.same({ want, want }, { S.action.base_scalar.cost, S.action.base_fn.cost })
        assert.are.same({ want, want }, { H.ns.SpendPoints(1.4, S.mana, class.abilities.base_fn), want })
    end)

    it("keeps a 0.5 cost without the flag a fraction and a 40 cost flat", function()
        assert.are.same({ math.floor(0.5 * BASE + 1e-6), 40 }, { S.action.half.cost, S.action.flat.cost })
    end)
end)
