-- tests/Forever/near_cost_engine_spec.lua (mana-regen plan, Task 4a fix 1): the engine's near-cost hold end to end
-- (Engine/Sim/Core.lua's branch before the 0.05 s rule) on a booted Fire Mage with a hand-set two-entry list, the mana
-- belief hand-set (VS.Power's floor and estimate, VS.Regen's rate) so the higher entry waits on mana alone, just under
-- its cost. With the estimate within EARLY_EXIT of the cost the pick stays first at the floor's wait (a countdown,
-- never shown ready early) over a ready lower entry; with the estimate at the floor the ready entry comes through.
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.mage_world")

local REGEN = 38 -- mana a second, casting or not
-- the floor under Fireball's cost: 0.32 s away (12 / 38), past EARLY_EXIT (0.2) and within one update (0.2). It was 8
-- (8 / 38 plus a 0.1 s tick pad) until L755 / L960: a pool with no tick seen pads nothing, so the distance is all regen.
local UNDER = 12

-- Boots, targets, hand-sets the mana belief (the floor `under` [UNDER] below Fireball's cost, the estimate `gap` above
-- the floor, `frac` of a mana above a whole floor if given), loads the list (`list` if given), calls `before(H)` if
-- given and runs one cycle; returns the first slot and the cost.
local function first(gap, frac, before, list, under)
    under = under or UNDER
    local C = mw.Fire
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    local cost = H.Hekili.State.action.fireball.cost
    local lo = frac and math.floor(cost) - under + frac or cost - under
    local power = { est = lo + gap, lo = lo, hi = lo + gap, conf = 1 }
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
        default = list or {
            { enabled = true, action = "fireball" },
            { enabled = true, action = "scorch" },
        },
    }
    H.Hekili:LoadScripts()
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    if before then
        before(H)
    end
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
            local slot = first(5) -- the estimate 7 mana short: 0.18 s; the floor 12 short: 0.32 s
            assert.are.equal("fireball", slot.actionName)
            assert.is_true(slot.wait > 0.2 and slot.wait < 0.4, slot.wait) -- the floor's wait: past EARLY_EXIT, never ready early
        end
    )

    it(
        "waits from the floor's fraction: a whole-mana read would lag it by up to 1 / regen, over the 0.05 s rule",
        function()
            local late, early = first(5, 0).wait, first(5, 0.9).wait
            assert.is_true(math.abs(late - early - 0.9 / REGEN) < 0.011, late - early) -- the wait rounds up to 0.01 s
        end
    )

    it("lets the ready lower entry through when the estimate is the floor (no mark)", function()
        local slot, cost = first(0)
        assert.is_true(cost > 150) -- Scorch's top rank, affordable at the floor
        assert.are.equal("scorch", slot.actionName)
        assert.are.equal(0, slot.wait)
    end)
end)

describe("the near-cost hold behind a running GCD (L628 option A)", function()
    local GCD_LEFT = 0.6
    -- the GCD runs GCD_LEFT more (the belief's GCD stubbed as VS.Power is); Fireball's floor reaches its cost 0.89 s
    -- away (34 under; 30 plus the tick pad before L755 / L960), its estimate 0.21 s away (8 under): the crossing falls
    -- under the GCD, as a free filler's GCD end meets a pick's resource crossing
    local function gcd(H)
        H.ns.VirtualState.GcdInfo = function(t)
            return t - (1.5 - GCD_LEFT), 1.5
        end
    end
    it("keeps the pick first over an entry ready at the GCD's end: the window opens where the GCD ends", function()
        local slot = first(26, nil, gcd, nil, 34)
        assert.is_true(slot.wait > GCD_LEFT - 0.01, slot.wait) -- the GCD reached the sim: whichever wins waits for it
        assert.are.equal("fireball", slot.actionName)
        assert.is_true(slot.wait > GCD_LEFT + 0.05 and slot.wait < 1.0, slot.wait) -- the floor's wait, past the GCD
    end)

    it("lets an entry ready before the GCD's end through (use_off_gcd): the hold covers the GCD's end on", function()
        local slot = first(26, nil, gcd, {
            { enabled = true, action = "fireball" },
            { enabled = true, action = "scorch", use_off_gcd = 1 },
        }, 34)
        assert.are.equal("scorch", slot.actionName)
    end)

    it("does not hold when the estimate reaches the cost past the GCD's end + EARLY_EXIT", function()
        local slot = first(0, nil, gcd, nil, 34) -- the estimate is the floor: 0.89 s, past 0.6 + 0.2
        assert.are.equal("scorch", slot.actionName)
    end)
end)

describe("the Clash setting on a booted Mage", function()
    -- the pick's Clash: Fireball (0.32 s on its floor, no near mark) is treated as ready `clash` sooner, so Scorch,
    -- ready 0.32 s sooner (under clash + the 0.05 s pad), does not displace it
    local function clashed(clash, key)
        key = key or "fireball"
        return function(H)
            local S = H.Hekili.State
            H.Hekili.Engine.settings.specs[S.spec.id].abilities[key].clash = clash
            assert.are.equal(clash, S:ClashOffset(key))
        end
    end

    it("keeps the pick over a later entry ready less than its Clash + 0.05 s sooner", function()
        local slot = first(0, nil, clashed(0.3))
        assert.are.equal("fireball", slot.actionName)
        assert.is_true(slot.wait > 0.3 and slot.wait < 0.35, slot.wait) -- the real wait: Clash moves only the comparison
    end)

    it("lets a later entry ready more than the pick's Clash + 0.05 s sooner through", function()
        local slot = first(0, nil, clashed(0.2))
        assert.are.equal("scorch", slot.actionName)
    end)

    -- the later entry's Clash: Fireball (off the GCD, 0.32 s on its floor) and Scorch at the GCD's end (0.29 s) are
    -- within the 0.05 s pad; Scorch's Clash 0.3 makes it ready sooner by more, so it takes over
    local function scorchClash(clash)
        local set = clashed(clash, "scorch")
        return function(H)
            H.ns.VirtualState.GcdInfo = function(t)
                return t - 1.21, 1.5 -- 0.29 s left
            end
            set(H)
        end
    end
    local OFF = { { enabled = true, action = "fireball", use_off_gcd = 1 }, { enabled = true, action = "scorch" } }

    it("lets a later entry with Clash take over a pick ready less than its Clash sooner", function()
        local slot = first(0, nil, scorchClash(0.3), OFF)
        assert.are.equal("scorch", slot.actionName)
        assert.is_true(slot.wait > 0.28 and slot.wait < 0.3, slot.wait) -- its real wait: the GCD's end
    end)

    it("keeps the pick over that entry with no Clash: under the 0.05 s pad", function()
        local slot = first(0, nil, scorchClash(0), OFF)
        assert.are.equal("fireball", slot.actionName)
    end)
end)
