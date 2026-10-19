-- tests/Forever/loop_shaman_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Shaman in each pack (tests/Forever/helpers/shaman_world.lua) against the harness's world; the mob swings at us
-- (Lightning Shield's charges spent by its hits), the world keeps the totem slots (W.summonTotem). `make check` runs 3
-- fights a pack (#slow); `make test-shaman` the 20 (#shaman). Each gate also asserts its flagged lines ran (review
-- focus 5).
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local sw = require("Forever.helpers.shaman_world")

local PACKS = { "Enhancement" }

describe("the Shaman loop worlds", function()
    for _, name in ipairs(PACKS) do
        it(name .. ": boots, and maps every ability the pack can recommend that the character knows", function()
            local C = sw[name]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for _, list in pairs(H.Hekili.DB.profile.packs[C.PACK].lists) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    if a and a.id and H.ctl.known[a.id] and not sw.MAP[entry.action] then
                        unmapped[#unmapped + 1] = entry.action
                    end
                end
            end
            assert.are.same({}, unmapped)
            assert.is_false(pcall(C.resolve, "not_an_ability", H))
        end)
    end
end)

describe("the headless Shaman gates, 3 fights a pack #slow", function()
    for _, name in ipairs(PACKS) do
        it(
            name .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = pack_gate.solo(name, sw[name], 3, nil, "seeds 1-3")
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)

describe("the headless Shaman gates, 20 fights a pack #shaman", function()
    for _, name in ipairs(PACKS) do
        it(name .. " solo, level 60, one mob, 20 fights of up to 3 minutes", function()
            local r, line = pack_gate.solo(name, sw[name], 20)
            assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
        end)
    end
end)
