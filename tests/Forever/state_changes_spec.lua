-- tests/Forever/state_changes_spec.lua: every state mutator the memoised cost relies on (Engine/Schema/Races.lua
-- M.Wrap keys on `state.changes` and query_time; DEVELOPMENT.md "Test first, headless") raises `state.changes`. A new
-- mutator in Engine/Sim/State.lua must bump the count and join this list. Headless Arms, so reset has a pack.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("state.changes, the memoised cost's key", function()
    local s
    setup(function()
        s = headless.new({ character = ww.character(), pack = ww.PACK }).Hekili.State
    end)

    -- the mutator's name, then its arguments; `prep` (name, arguments) runs before the count is read
    local MUTATORS = {
        { "applyBuff", "casting", 1.5 },
        { "removeBuff", "casting" },
        { "addStack", "casting", 1.5, 1 },
        { "removeStack", "casting" },
        { "applyDebuff", "target", "casting", 1.5 },
        { "removeDebuff", "target", "casting" },
        { "removeDebuffStack", "target", "sunder_armor", 1, prep = { "applyDebuff", "target", "sunder_armor", 1.5, 3 } }, -- max_stack 5, 3 stacks stay: the direct-count branch
        { "setCooldown", "heroic_strike", 1.5 },
        { "spendCharges", "heroic_strike", 1 },
        { "gainCharges", "heroic_strike", 1 },
        { "gainChargeTime", "heroic_strike", 1 },
        { "reduceCooldown", "heroic_strike", 1 },
        { "gain", 1, "rage" },
        { "spend", 1, "rage" },
        { "summonPet", "pet_a", 10 },
        { "dismissPet", "pet_a" },
        { "summonTotem", "totem_a", nil, 10 },
        { "setStance", "battle" },
        { "advance", 0.1 },
        { "reset" },
    }

    local function call(m)
        s[m[1]](unpack(m, 2, 5))
    end

    for _, m in ipairs(MUTATORS) do
        it("is raised by " .. m[1], function()
            if m.prep then
                call(m.prep)
            end
            local n = s.changes
            call(m)
            assert.is_true(s.changes > n, m[1] .. " left state.changes at " .. tostring(n))
        end)
    end
end)
