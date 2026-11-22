-- tests/Forever/combo_refresh_spec.lua: core's power handler forces one refresh when the player's combo points change
-- (UNIT_POWER_FREQUENT with the "COMBO_POINTS" token), end to end with a real pack loaded, and none for an energy tick.
local headless = require("Game.harness.headless")
local w = require("Forever.helpers.rogue_world")
local dlw = require("Forever.helpers.druid_loop_world")

describe("combo point refresh", function()
    it("core forces exactly one update for COMBO_POINTS and none for ENERGY", function()
        local H = headless.new({ character = w.Combat.character(), pack = w.Combat.PACK })
        assert.are.same({}, H.loadErrors)
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
        local forced = {}
        H.Hekili.ForceUpdate = function(_, event, super)
            forced[#forced + 1] = tostring(event) .. ":" .. tostring(super)
        end
        H.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
        assert.are.same({}, forced)
        H.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        assert.are.same({ "UNIT_POWER_FREQUENT:true" }, forced) -- the whole list: a pack hook beside core's fails here
        assert.are.same({}, H.errors)
    end)

    -- (L1681 a) the event's upper-case token names the pool core compares, never the displayed one
    it("in Cat Form a MANA event compares mana, never energy; a token core does not know compares nothing", function()
        local H = headless.new({ character = dlw.Feral.character(), pack = dlw.Feral.PACK })
        assert.are.same({}, H.loadErrors)
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
        local I = H.ns.VirtualStateInternal
        local function lose(powerType, amount)
            local r = assert(I.res.slotOf[powerType])
            I.ResourceShift(r, -amount, H.ctl.now, H.ns.VirtualState.Obs.CastSuccess)
        end
        local forced = 0
        H.Hekili.ForceUpdate = function()
            forced = forced + 1
        end
        local function fire(token)
            forced = 0
            H.Fire("UNIT_POWER_FREQUENT", "player", token)
            return forced
        end
        for _, token in ipairs({ "MANA", "ENERGY", "NO_SUCH_POWER" }) do
            fire(token) -- the first read
        end
        lose(3, 30)
        assert.are.same({ mana = 0, unknown = 0, energy = 1, combo = 1 }, {
            mana = fire("MANA"),
            unknown = fire("NO_SUCH_POWER"),
            energy = fire("ENERGY"),
            combo = fire("COMBO_POINTS"),
        })
        lose(0, 100)
        assert.are.same({ energy = 0, mana = 1 }, { energy = fire("ENERGY"), mana = fire("MANA") })
        assert.are.same({}, H.errors)
    end)
end)
