-- tests/Forever/spend_of_spec.lua (dry-forecast, engine pass C5): state.SpendOf, the one read of an ability's declared
-- spend in the sim. An ability's `spend` answers through its metatable and the cost modifiers' wrapper
-- (Engine/Schema/Races.lua M.Wrap), so it is a number or nil, never a function: the resource is always the ability's
-- `spendType`, else the class's primary resource. Checked on every ability of one world per class.
local headless = require("Game.harness.headless")

local WORLDS = {
    { "rogue_world", "Assassination" },
    { "mage_world", "Arcane" },
    { "warlock_world", "Affliction" },
    { "hunter_world", "Survival" },
    { "shaman_world", "Enhancement" },
    { "priest_world", "Shadow" },
    { "paladin_world", "HolyShock" },
    { "warrior_world", "Fury" },
    { "druid_loop_world", "Feral" },
}

describe("state.SpendOf", function()
    for _, w in ipairs(WORLDS) do
        it("answers each " .. w[2] .. " ability's declared spend, a number or nil, and its resource", function()
            local C = require("Forever.helpers." .. w[1])[w[2]]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local S, class = H.Hekili.State, H.Hekili.Class
            assert.is_function(S.SpendOf)
            local n = 0
            for key, a in pairs(class.abilities) do
                local c, r = S.SpendOf(a)
                assert.is_true(c == nil or type(c) == "number", tostring(key) .. ": " .. type(c))
                assert.are.equal(a.spend, c, tostring(key))
                assert.are.equal(a.spendType or class.primaryResource, r, tostring(key))
                n = n + (c and 1 or 0)
            end
            assert.is_true(n > 5)
        end)
    end
end)
