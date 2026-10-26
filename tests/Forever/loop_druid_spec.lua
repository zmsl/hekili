-- tests/Forever/loop_druid_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Druid in each pack (tests/Forever/helpers/druid_loop_world.lua) against the harness's world. `make check` runs 3
-- fights a pack (#slow); `make test-druid` the 20 (#druid). Each gate also asserts its flagged lines ran (review focus
-- 5: run A's in-combat ticks whose first record has `focus` set).
-- The 20-fight gates live one pack a file (loop_druid_<pack>_spec.lua), so `make test-druid` runs them in parallel.
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local scenarios = require("Game.harness.scenarios")
local dlw = require("Forever.helpers.druid_loop_world")

local PACKS = { "Feral", "Guardian", "Balance" }
-- Guardian (wowsims.com) is reported, not gated (Task 7g): rage-starved (11.25 a 2.5 s swing, no rage from damage
-- taken in the class file), its first icon waits for rage between Primal Bite and Lacerate, which the usability
-- ladder's rage rungs cannot split: agreement 0.805 and cost refusals 10.5 (the oracle's 6.3) at seeds 1-3, under
-- the gate's 0.85. Its engine health and focus are still asserted. Central fix 22 round 2 (presses resolve from the
-- current state, not Update's leftover prediction): seeds 1-3 0.811 -> 0.899, the 20 fights 0.774 -> 0.850 (at the
-- gate, so still reported).
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

describe("the Guardian loop world's press", function()
    -- review fix: the press is checked at the cost the client sees (0 under Clearcasting); the swing prices it
    it("accepts a Maul pressed under Clearcasting with rage below its cost, and takes nothing at the queue", function()
        local C = dlw.Guardian
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local VS = H.ns.VirtualState
        local Aura = VS.Aura
        VS.Aura = function() -- Clearcasting up on the truth instance
            return true
        end
        local p = C.resolve("maul", H)
        VS.Aura = Aura
        local W = scenarios.world(setmetatable({ power = 5, form = C.character().form }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        local ok, why = W.press(us, "maul", p)
        assert.is_true(ok, tostring(why))
        assert.are.equal(5, us.power)
    end)
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
