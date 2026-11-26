-- tests/Forever/loop_hunter_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Hunter in each pack (tests/Forever/helpers/hunter_world.lua) against the harness's world; the turret worlds shoot
-- Auto Shots on the ranged hand (W.startRanged), the mob swings at us (our dodges open Mongoose Bite). `make check`
-- runs 3 fights a pack (#slow); `make test-hunter` the 20 (#hunter). Each gate also asserts its flagged lines ran
-- (review focus 5).
-- The 20-fight gates live one pack a file (loop_hunter_<pack>_spec.lua), so `make test-hunter` runs them in parallel.
local headless = require("Game.harness.headless")
local loop = require("Game.harness.loop")
local pack_gate = require("Forever.helpers.pack_gate")
local hw = require("Forever.helpers.hunter_world")

-- pack, the label its line prints
local PACKS = { { "Survival", "Survival" } }
-- every pack: the weave pack, then wowsims's non-weave builds (owner 2026-11-12, ledger L661); the Beast Mastery and
-- Marksmanship weave packs are retired (L1154)
local ALL = {
    PACKS[1],
    { "BeastMasteryTurret", "Beast Mastery Turret" },
    { "MarksmanshipTurret", "Marksmanship Turret" },
    { "SurvivalTurret", "Survival Turret" },
    { "SurvivalMelee", "Survival Melee" },
}

describe("the Hunter loop worlds", function()
    for _, pk in ipairs(ALL) do
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

    -- Gap BV: the Survival weave export carries Resourcefulness (440529) 2/2; wowsims cuts the strikes' cost 60% under
    -- it (its log's 40-mana Raptor Strike). World and belief agree.
    it("price Raptor Strike under the builds' Resourcefulness and Efficiency, the world and the pack alike", function()
        local out = {}
        for _, pk in ipairs(PACKS) do
            local C = hw[pk[1]]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            out[pk[1]] = { C.resolve("raptor_strike", H).cost, H.Hekili.State.action.raptor_strike.cost }
        end
        assert.are.same({ Survival = { 40, 40 } }, out)
        -- every Resourcefulness-cut ability of the Survival kit: the world's price is the pack's (the client pays whole
        -- mana, so the world's is floored)
        local C = hw.Survival
        local H = headless.new({ character = C.character(), pack = C.PACK })
        for _, k in ipairs({ "mongoose_bite", "wing_clip", "strider_kick" }) do
            assert.are.equal(H.Hekili.State.action[k].cost, math.floor(C.resolve(k, H).cost), k)
        end
    end)

    -- Trainer-taught, as wowsims's character (its APL names resolve to the trainer rank, book_ranks.go): every Hunter
    -- log casts Serpent Sting rank 8 (13555) for 230 (Marksmanship's Efficiency 4/5: 202.4) and Aspect of the Hawk
    -- rank 6 (14322), never the Guide books' 25295 / 25296
    it("know no book rank: Serpent Sting is rank 8's price, the world and the pack alike", function()
        local out = {}
        for _, pk in ipairs(ALL) do
            local C = hw[pk[1]]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            out[pk[1]] = {
                ("%.2f"):format(C.resolve("serpent_sting", H).cost),
                ("%.2f"):format(H.Hekili.State.action.serpent_sting.cost),
                H.ctl.known[25295] or false,
                H.ctl.known[25296] or false,
            }
        end
        local rank8, mm = { "230.00", "230.00", false, false }, { "202.40", "202.40", false, false }
        assert.are.same({
            Survival = rank8,
            BeastMasteryTurret = rank8,
            MarksmanshipTurret = mm,
            SurvivalTurret = rank8,
            SurvivalMelee = rank8,
        }, out)
    end)

    -- Each world's pool and regen are its wowsims log's (OtherID 2 regen ticks, 0.1 s apart): the max mana, the casting
    -- tick (Tag 1; with each casting-share aura's boost) and the tick outside the five-second rule (Tag 2)
    for _, pk in ipairs(ALL) do
        it(pk[1] .. ": the pool and the five-second rule's rates are its wowsims log's", function()
            local Wd = hw[pk[1]].WORLD
            local f = Wd.fsr[0]
            local spec = "hunter_" .. pk[2]:lower():gsub(" ", "_")
            local log = assert(io.open("tests/Forever/wowsims/" .. spec .. ".log")):read("*a")
            assert.are.equal(
                tonumber(log:match("Spent [%d.]+ mana from {SpellID: %d+} %([%d.]+ %-%-> [%d.]+%) of (%d+) total")),
                Wd.max
            )
            local rows = { { 1, f[2] }, { 2, f[1] + f[2] } }
            for _, a in pairs(f.auras or {}) do -- S = f[1] / (1 - c) with no static share c here
                rows[#rows + 1] = { 1, f[2] + a.share * f[1] }
            end
            for _, t in ipairs(rows) do
                local row = ("Gained %.3f mana from {OtherID: 2, Tag: %d}"):format(t[2] / 10, t[1])
                assert.is_truthy(log:find(row, 1, true), row)
            end
        end)
    end

    -- The Beast Within (owner L1105): every mana cost -50% for Bestial Wrath's 18 s, its own cast at full price. The
    -- world's truth: the charge (`price`) and the client's answer; the BM Turret build has no Efficiency (189 whole).
    it("halves every cost during The Beast Within: the world's charge and the client's answer", function()
        local C = hw.BeastMasteryTurret
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local by = {}
        for _, u in ipairs(C.usable(H)) do
            by[u[1]] = u[2]
        end
        local id = H.Hekili.Class.abilities.arcane_shot.id
        local W, e = { t = 10, truth = {} }, { guid = "Player-1", auras = {} }
        local shot = C.resolve("arcane_shot", H)
        assert.are.same({ 189, 189 }, { shot.cost, shot.price(W, e) })
        assert.is_false((by[id](W, e, 100)))
        local bw = C.resolve("bestial_wrath", H)
        assert.are.equal(206, bw.price(W, e)) -- its own cast before its window
        bw.effect(W, e)
        assert.are.same({ 94.5, 206 * 0.5 }, { shot.price(W, e), bw.price(W, e) })
        assert.is_true((by[id](W, setmetatable({}, { __index = e }), 100)))
        W.t = 28.01
        assert.are.equal(189, shot.price(W, e))
        assert.is_false((by[id](W, e, 100)))
    end)

    -- The observer hands the usability answers a proxy of us (its own view of our form), never the entity itself, so
    -- a window that tests the swing's target by identity never opens for the client.
    it("answers Mongoose Bite's window through the observer's proxy of us: our dodge within 5 s", function()
        local C = hw.Survival
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local by = {}
        for _, u in ipairs(C.usable(H)) do
            by[u[1]] = u[2]
        end
        local id = H.Hekili.Class.abilities.mongoose_bite.id
        local e = { guid = "Player-1" }
        local W = { t = 10, truth = {} }
        assert.is_false((by[id](W, e, 100)))
        W.truth[1] = { t = 8, kind = "swing", dst = e, act = "DODGE" }
        assert.is_true((by[id](W, e, 100)))
        assert.is_true((by[id](W, setmetatable({}, { __index = e }), 100)))
    end)

    it("presses Mongoose Bite through the client: the dodge reaches IsSpellUsable, the APL's line fires", function()
        local L = loop.new(hw.Survival)
        local presses = 0
        local run = loop.run(L, 1, { duration = 120 }, { { H = L.us } })
        for _, k in pairs(run.pressed) do
            if k == "mongoose_bite" then
                presses = presses + 1
            end
        end
        assert.is_true(presses > 0, "Mongoose Bite presses in 120 s at seed 1: " .. presses)
    end)
end)

describe("the headless Hunter gates, 3 fights a pack #slow", function()
    for _, pk in ipairs(ALL) do
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

-- Gap 13 (wowsims unitDistance): the world at 25 yd, then in melee. Survival (wowsims.com)'s melee lines are the
-- translator's `target.within5` (the weave's move variant's in-melee arm; the loops run Movement OFF), read against the
-- engine's range bracket. Twice: on the DB2's ranges (Combat Range 0-5), and live-shaped: the live client reads
-- maxRange 0 for a melee strike and answers its range check against 5 yd (ForeverProbe dump 2026-11-07, Warrior).
describe("the Hunter at range, then in melee", function()
    for _, live in ipairs({ false, true }) do
        it(
            "brackets the distance from the kit's ranges and opens the melee list only in reach"
                .. (live and ", live-shaped" or ""),
            function()
                local loop = require("Game.harness.loop")
                local fake = require("Game.State.helpers.fake_api")
                local base = hw.Survival
                local MOVE, SECRET = loop.PULL + 12, loop.PULL + 20
                local C = setmetatable({}, { __index = base })
                function C.character()
                    local c = base.character()
                    for _, key in
                        ipairs(live and { "raptor_strike", "mongoose_bite", "strider_kick", "wing_clip" } or {})
                    do
                        for _, id in ipairs(hw.Survival.IDS[key] or {}) do
                            c.ranges[id] = { 0, 0, 5 }
                        end
                    end
                    return c
                end
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
                    -- the bracket is the variant's in-melee arm, its own line ending in the term (R51: the move arm,
                    -- `toggle.movement&(<the weave's move>)`, is a copy where the weave group is called; Wing Clip keeps its
                    -- Strider Kick condition before the term)
                    gated = gated + (("&" .. e.criteria):match("&target%.within5$") and 1 or 0)
                end
                assert.are.equal(5, gated) -- Raptor Strike, Mongoose Bite, Strider Kick, Immolation Trap, Wing Clip
                local MELEE = { mongoose_bite = true, strider_kick = true, immolation_trap = true, wing_clip = true }
                local seen = { far = {}, near = {}, secret = {}, aged = {} }
                local run = loop.run(L, 1, {
                    duration = 30,
                    on = function(r, steps, t)
                        if t >= SECRET then
                            H.ctl.distance.target = fake.SECRET -- every range read secret from here
                        end
                        -- the pull's and the move's first second, and the second around the 1.5 s age-out (review I1)
                        if
                            t < loop.PULL + 1
                            or (t >= MOVE and t < MOVE + 1)
                            or (t >= SECRET + 1 and t < SECRET + 2)
                        then
                            return
                        end
                        local phase = t < MOVE and "far"
                            or (t < SECRET and "near" or (t < SECRET + 1 and "secret" or "aged"))
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
                -- [20, 25]: LibRangeCheck's bracket (the harness double; range plan R2); Raptor Strike out of reach
                assert.are.same({ false, true, false, false, 22.5 }, view(seen.far))
                assert.are.same({ true, false, true, true, 2.5 }, view(seen.near)) -- [0, 5]
                assert.are.same({ true, false, true, true, 2.5 }, view(seen.secret)) -- the last plain bracket stays
                -- 1.5 s with no plain answer: unknown (review I1), which never blocks
                local aged = view(seen.aged)
                assert.are.same({ true, true, true, true }, { aged[1], aged[2], aged[3], aged[4] }, aged[5])
                assert.is_true(seen.aged.melee > 0)
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
            end
        )
    end
end)
