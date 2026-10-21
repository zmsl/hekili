-- tests/Forever/loop_hunter_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Hunter in each pack (tests/Forever/helpers/hunter_world.lua) against the harness's world; the turret worlds shoot
-- Auto Shots on the ranged hand (W.startRanged), the mob swings at us (our dodges open Mongoose Bite). `make check`
-- runs 3 fights a pack (#slow); `make test-hunter` the 20 (#hunter). Each gate also asserts its flagged lines ran
-- (review focus 5).
-- The 20-fight gates live one pack a file (loop_hunter_<pack>_spec.lua), so `make test-hunter` runs them in parallel.
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

-- Gap 13 (wowsims unitDistance): the world at 25 yd, then in melee. Survival (wowsims.com)'s melee lines carry the
-- translator's `target.within5`, read against the engine's range bracket.
describe("the Hunter at range, then in melee", function()
    it("brackets the distance from the kit's ranges and opens the melee list only in reach", function()
        local loop = require("Game.harness.loop")
        local fake = require("Game.State.helpers.fake_api")
        local base = hw.Survival
        local MOVE, SECRET = loop.PULL + 12, loop.PULL + 20
        local C = setmetatable({}, { __index = base })
        C.WORLD = setmetatable({
            distance = 25,
            script = function(W, us)
                base.WORLD.script(W, us)
                W.at(MOVE, function()
                    W.moveTo(us, 5)
                end)
            end,
        }, { __index = base.WORLD })
        local L = loop.new(C)
        local H = L.us
        local pack = H.Hekili.Engine.settings.packs[C.PACK]
        local gated = 0
        for _, e in ipairs(pack.lists.default) do
            gated = gated + (e.criteria == "target.within5" and 1 or 0)
        end
        assert.are.equal(4, gated) -- Mongoose Bite, Strider Kick, Immolation Trap, Wing Clip
        local MELEE = { mongoose_bite = true, strider_kick = true, immolation_trap = true, wing_clip = true }
        local seen = { far = {}, near = {}, secret = {} }
        local run = loop.run(L, 1, {
            duration = 30,
            on = function(r, steps, t)
                if t < loop.PULL + 1 or (t >= MOVE and t < MOVE + 1) then -- the pull's and the move's first second
                    return
                end
                local phase = t < MOVE and "far" or (t < SECRET and "near" or "secret")
                if t >= SECRET then
                    H.ctl.distance.target = fake.SECRET -- every range read secret from here
                end
                local tg = H.Hekili.State.target
                local s = seen[phase]
                -- each read's one value over the phase ("mixed" when it changed)
                local S = H.Hekili.State
                local ok, why = S:IsUsable("raptor_strike") -- on the next swing: the bracket's reach
                local reads = {
                    within = tg.within5,
                    outside = tg.outside5,
                    usable = ok or why ~= "target beyond melee range", -- (a queued strike refuses too)
                    inRange = S.action.raptor_strike.in_range,
                }
                for key, v in pairs(reads) do
                    if s[key] == nil then
                        s[key] = v
                    elseif s[key] ~= v then
                        s[key] = "mixed"
                    end
                end
                s.distance = tg.distance
                local first = steps[1].q.name[1]
                s.melee = (s.melee or 0) + (MELEE[first] and 1 or 0)
            end,
        }, { { H = H } })
        local function view(x)
            return { x.within, x.outside, x.usable, x.inRange, x.distance }
        end
        -- [8, 35]: in the shots' band; Raptor Strike out of reach
        assert.are.same({ false, true, false, false, 21.5 }, view(seen.far))
        assert.are.same({ true, false, true, true, 2.5 }, view(seen.near)) -- [0, 5]
        assert.are.same({ true, false, true, true, 2.5 }, view(seen.secret)) -- the last plain bracket stays
        assert.are.equal(0, seen.far.melee)
        assert.is_true(seen.near.melee > 0)
        assert.is_nil(run.refused.range) -- nothing recommended out of its range, Raptor Strike included
        assert.are.same({}, H.errors)
        -- a new target with every range read secret: unknown, and unknown never blocks
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.equal("unknown", H.ns.VirtualState.TargetRange().basis)
        local S = H.Hekili.State
        local _, why = S:IsUsable("raptor_strike")
        assert.are.same(
            { true, true, true },
            { why ~= "target beyond melee range", S.target.within5, S.target.outside5 }
        )
    end)
end)
