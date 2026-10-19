-- tests/Forever/loop_hunter_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Hunter in each pack (tests/Forever/helpers/hunter_world.lua) against the harness's world; the turret worlds shoot
-- Auto Shots on the ranged hand (W.startRanged), the mob swings at us (our dodges open Mongoose Bite). `make check`
-- runs 3 fights a pack (#slow); `make test-hunter` the 20 (#hunter). Each gate also asserts its flagged lines ran
-- (review focus 5).
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local hw = require("Forever.helpers.hunter_world")

-- pack, the label its line prints
local PACKS = { { "BeastMastery", "Beast Mastery" }, { "Marksmanship", "Marksmanship" }, { "Survival", "Survival" } }

describe("the Hunter loop worlds", function()
    for _, pk in ipairs(PACKS) do
        local name = pk[1]
        it(name .. ": boots, and maps every ability the pack can recommend that the character knows", function()
            local C = hw[name]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for _, list in pairs(H.Hekili.DB.profile.packs[C.PACK].lists) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    if a and a.id and H.ctl.known[a.id] and not hw.MAP[entry.action] then
                        unmapped[#unmapped + 1] = entry.action
                    end
                end
            end
            assert.are.same({}, unmapped)
            assert.is_false(pcall(C.resolve, "not_an_ability", H))
        end)
    end
end)

describe("the headless Hunter gates, 3 fights a pack #slow", function()
    for _, pk in ipairs(PACKS) do
        it(
            pk[2] .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = pack_gate.solo(pk[2], hw[pk[1]], 3, nil, "seeds 1-3")
                print(pk[2] .. " focus ticks: " .. r.focus)
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)

describe("the headless Hunter gates, 20 fights a pack #hunter", function()
    for _, pk in ipairs(PACKS) do
        it(pk[2] .. " solo, level 60, one mob, 20 fights of up to 3 minutes", function()
            local r, line = pack_gate.solo(pk[2], hw[pk[1]], 20)
            print(pk[2] .. " focus ticks: " .. r.focus)
            assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
        end)
    end
end)
