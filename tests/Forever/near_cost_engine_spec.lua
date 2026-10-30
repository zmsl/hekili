-- tests/Forever/near_cost_engine_spec.lua (mana-regen plan, Task 4a fix 1): the engine's near-cost hold end to end
-- (Engine/Sim/Core.lua's branch before the 0.05 s rule) on a booted Fire Mage with a hand-set two-entry list, the mana
-- belief hand-set (VS.Power's floor and estimate, VS.Regen's rate) so the higher entry waits on mana alone, just under
-- its cost. With the estimate within EARLY_EXIT of the cost the pick stays first at the floor's wait (a countdown,
-- never shown ready early) over a ready lower entry; with the estimate at the floor the ready entry comes through.
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.mage_world")

local REGEN = 38 -- mana a second, casting or not
local UNDER = 8 -- the floor under Fireball's cost: 0.31 s away (8 / 38 plus the forecast's 0.1 s tick), past EARLY_EXIT
-- (0.2) and within one update (0.2)

-- Boots, targets, hand-sets the mana belief (the floor `UNDER` below Fireball's cost, the estimate `gap` above the
-- floor), loads the list and runs one cycle; returns the first slot and the cost.
local function first(gap)
    local C = mw.Fire
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    H.Hekili.combatRate = 0.2
    local cost = H.Hekili.State.action.fireball.cost
    local power = { est = cost - UNDER + gap, lo = cost - UNDER, hi = cost - UNDER + gap, conf = 1 }
    local regen = { est = REGEN, lo = REGEN, hi = REGEN, conf = 1 }
    local VS = H.ns.VirtualState
    VS.Power = function()
        return power
    end
    VS.Regen = function()
        return regen
    end
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    local t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    H.Hekili.DB.profile.packs[C.PACK].lists = {
        default = {
            { enabled = true, action = "fireball" },
            { enabled = true, action = "scorch" },
        },
    }
    H.Hekili:LoadScripts()
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    assert(headless.cycle(H, t + 0.2))
    assert.are.same({}, H.errors)
    local slot = H.Hekili.Engine.Output.Primary.recs[1]
    assert.is_table(slot)
    return slot, cost
end

describe("the engine's near-cost hold on a booted Mage", function()
    it(
        "keeps the higher entry first at the floor's wait when its estimate reaches the cost within EARLY_EXIT",
        function()
            local slot = first(5) -- the estimate 3 mana short: 0.18 s; the floor 8 short: 0.31 s
            assert.are.equal("fireball", slot.actionName)
            assert.is_true(slot.wait > 0.2 and slot.wait < 0.4, slot.wait) -- the floor's wait: past EARLY_EXIT, never ready early
        end
    )

    it("lets the ready lower entry through when the estimate is the floor (no mark)", function()
        local slot, cost = first(0)
        assert.is_true(cost > 150) -- Scorch's top rank, affordable at the floor
        assert.are.equal("scorch", slot.actionName)
        assert.are.equal(0, slot.wait)
    end)
end)
