-- tests/Forever/loop_paladin_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Paladin in each pack (tests/Forever/helpers/paladin_world.lua) against the harness's world; the mob swings at us
-- (Protection's Holy Shield charges spent by its blocks). `make check` runs 3 fights a pack (#slow); `make test-paladin`
-- the 20 (#paladin). Each gate also asserts its flagged lines ran (review focus 5).
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local pw = require("Forever.helpers.paladin_world")

local PACKS = { "Retribution", "Protection" } -- the contents (paladin_world.lua): each on its wowsims.com pack

describe("the Paladin loop worlds", function()
    for _, name in ipairs(PACKS) do
        it(name .. ": boots, and maps every ability the pack can recommend that the character knows", function()
            local C = pw[name]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for _, list in pairs(H.Hekili.DB.profile.packs[C.PACK].lists) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    if a and a.id and H.ctl.known[a.id] and not pw.MAP[entry.action] then
                        unmapped[#unmapped + 1] = entry.action
                    end
                end
            end
            assert.are.same({}, unmapped)
            assert.is_false(pcall(C.resolve, "not_an_ability", H))
        end)
    end
end)

describe("the Paladin world's Judgement", function()
    it("returns Sanctified Judgement's mana at 3/3, as the class file believes (wowsims's log: 161.28)", function()
        local C = pw.Retribution
        local c = C.character()
        c.talents = { [1310735] = 1, [20101] = 5, [1311074] = 3 } -- Twist of Light, Benediction 5/5, Sanctified 3/3
        local H = headless.new({ character = c, pack = C.PACK })
        local seal = H.Hekili.Class.auras.seal_of_command.id
        local e, gained = { auras = { [seal] = { stacks = 1 } } }, {}
        local W = { t = 0, emit = function() end, hit = function() end }
        function W.gain(_, n)
            gained[#gained + 1] = n
        end
        C.resolve("judgement", H).effect(W, e)
        assert.are.equal(1, #gained)
        assert.is_true(math.abs(gained[1] - 161.28) < 1e-6, tostring(gained[1]))
        c.talents[1311074] = 2 -- a chance below 3/3: the world, as the belief, returns nothing
        H = headless.new({ character = c, pack = C.PACK })
        gained = {}
        C.resolve("judgement", H).effect(W, e)
        assert.are.same({}, gained)
    end)
end)

describe("the headless Paladin gates, 3 fights a pack #slow", function()
    for _, name in ipairs(PACKS) do
        it(
            name .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = pack_gate.solo(name, pw[name], 3, nil, "seeds 1-3")
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)

describe("the headless Paladin gates, 20 fights a pack #paladin", function()
    for _, name in ipairs(PACKS) do
        it(name .. " solo, level 60, one mob, 20 fights of up to 3 minutes", function()
            local r, line = pack_gate.solo(name, pw[name], 20)
            assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
        end)
    end
end)
