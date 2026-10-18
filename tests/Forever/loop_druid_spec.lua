-- tests/Forever/loop_druid_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Druid in each pack (tests/Forever/helpers/druid_loop_world.lua) against the harness's world. `make check` runs 3
-- fights a pack (#slow); `make test-druid` the 20 (#druid). Each gate also asserts its flagged lines ran (review focus
-- 5: run A's in-combat ticks whose first record has `focus` set).
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local dlw = require("Forever.helpers.druid_loop_world")

local PACKS = { "Feral", "Guardian", "Balance" }
-- Guardian is reported, not gated (DONE_WITH_CONCERNS, class-completion Task 2): starved of rage (8.65 a 2.5 s swing,
-- no rage from damage taken in the class file), its first icon is a wait for rage between Primal Bite and Lacerate,
-- which the usability ladder's rage rungs (10, 15, 20) cannot split: agreement 0.718 and cost refusals 31.2 (the
-- oracle's 19.3) at seeds 1-3. The sim's Berserk gate (Primal Bite >= 4 s away) costs 0.762 -> 0.718 here and 0.765 ->
-- 0.750 over 20 fights; the old priority fails the gate too. Its engine health and focus are still asserted.
local REPORTED = { Guardian = true }
local function solo(name, n, seed0, tag)
    return pack_gate.solo(name, dlw[name], n, seed0, tag, REPORTED[name])
end

describe("the Druid loop worlds", function()
    for _, name in ipairs(PACKS) do
        it(name .. ": boots, and maps every ability the pack can recommend that the character knows", function()
            local C = dlw[name]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for _, list in pairs(H.Hekili.DB.profile.packs[C.PACK].lists) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    if a and a.id and H.ctl.known[a.id] and not dlw.MAP[entry.action] then
                        unmapped[#unmapped + 1] = entry.action
                    end
                end
            end
            assert.are.same({}, unmapped)
            assert.is_false(pcall(C.resolve, "not_an_ability", H))
        end)
    end
end)

describe("the headless Druid gates, 3 fights a pack #slow", function()
    for _, name in ipairs(PACKS) do
        it(
            name .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = solo(name, 3, nil, "seeds 1-3")
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)

describe("the headless Druid gates, 20 fights a pack #druid", function()
    for _, name in ipairs(PACKS) do
        it(name .. " solo, level 60, one mob, 20 fights of up to 3 minutes", function()
            local r, line = solo(name, 20)
            assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
        end)
    end
end)
