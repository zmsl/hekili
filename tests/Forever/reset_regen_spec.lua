-- tests/Forever/reset_regen_spec.lua (border batch 2, Part A review M1): a real `state.reset` stores the regen read's
-- trailing slots where the sim's forecast reads them: slot 3 the five-second window's end (`fsr_until`), 4 the decay
-- anchor (`decay_anchor`), 5 the taken rate (`taken_rate`), per branch of the reset (mana's GetManaRegen, a
-- regenerating pool's GetPowerRegenForPowerType, a regen-model pool's anchor/rate read). Distinct nonzero tails, so a
-- swapped slot fails.
local headless = require("Game.harness.headless")

local WORLDS = {
    { "Forever.helpers.warrior_world", nil, "rage", nil }, -- the regen-model branch: anchor and rate only
    { "Forever.helpers.rogue_world", "Combat", "energy", 101 },
    { "Forever.helpers.priest_world", "Smite", "mana", 101 },
}

describe("the reset's regen tail (border batch 2)", function()
    for _, w in ipairs(WORLDS) do
        it(("stores slots 3, 4 and 5 into the %s resource"):format(w[3]), function()
            local world = require(w[1])
            local c = w[2] and world[w[2]] or world
            local H = headless.new({ character = c.character(), pack = c.PACK })
            assert.are.same({}, H.loadErrors)
            assert(headless.cycle(H, H.ctl.now + 0.2))
            local VS = H.ns.VirtualState
            VS.FsrUntil = function()
                return 101
            end
            VS.DecayAnchor = function()
                return 7
            end
            VS.TakenRate = function()
                return 0.4
            end
            H.Hekili.State.reset("Primary", true)
            local res = H.Hekili.Class.resources[w[3]].state
            assert.are.same(
                { w[4], 7, 0.4 },
                { rawget(res, "fsr_until"), rawget(res, "decay_anchor"), rawget(res, "taken_rate") }
            )
        end)
    end
end)
