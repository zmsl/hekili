-- tests/Forever/loop_rogue_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Rogue in each pack (tests/Forever/helpers/rogue_world.lua) against the harness's world. `make check` runs 3 fights a
-- pack (#slow); `make test-rogue` the 20 (#rogue). Each gate also asserts its flagged lines ran (review focus 5: run
-- A's in-combat ticks whose first record has `focus` set).
-- The 20-fight gates live one pack a file (loop_rogue_<pack>_spec.lua), so `make test-rogue` runs them in parallel.
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local rw = require("Forever.helpers.rogue_world")

local PACKS = { "Combat", "Assassination", "Subtlety" } -- rogue_world contents, each on its "<Spec> (wowsims.com)" pack

describe("the Rogue loop worlds", function()
    for _, name in ipairs(PACKS) do
        it(name .. ": boots, and maps every ability the pack can recommend that the character knows", function()
            local C = rw[name]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for _, list in pairs(H.Hekili.DB.profile.packs[C.PACK].lists) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    if a and a.id and H.ctl.known[a.id] and not rw.MAP[entry.action] then
                        unmapped[#unmapped + 1] = entry.action
                    end
                end
            end
            assert.are.same({}, unmapped)
            assert.is_false(pcall(C.resolve, "not_an_ability", H))
        end)
    end
end)

describe("the headless Rogue gates, 3 fights a pack #slow", function()
    for _, name in ipairs(PACKS) do
        it(
            name .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = pack_gate.solo(name, rw[name], 3, nil, "seeds 1-3")
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)
