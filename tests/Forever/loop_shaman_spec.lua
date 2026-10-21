-- tests/Forever/loop_shaman_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Shaman in each pack (tests/Forever/helpers/shaman_world.lua) against the harness's world; the mob swings at us
-- (Lightning Shield's charges spent by its hits), the world keeps the totem slots (W.summonTotem). `make check` runs 3
-- fights a pack (#slow); `make test-shaman` the 20 (#shaman). Each gate also asserts its flagged lines ran (review
-- focus 5).
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local sw = require("Forever.helpers.shaman_world")

local PACKS = { "Enhancement", "Elemental" }

describe("the Shaman loop worlds", function()
    -- A shock's press sends both shocks' ranks (the shared category) but is priced by its own rank: at level 30 the
    -- highest Flame Shock is rank 3 (8053, 160 mana in the DB2), not the top rank's 410.
    it("prices a shock by its own known rank", function()
        local ws = require("Forever.helpers.wowsims")
        local C = ws.content(sw.Enhancement, { level = 30, learn = ws.learn("SHAMAN") })
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local p = C.resolve("flame_shock", H)
        assert.are.same({ 8053, 160 }, { p.spell, p.cost })
        assert.are.equal(13, #p.ids) -- Earth Shock's 7 ranks and Flame Shock's 6
    end)

    -- Elemental's world without a pack (its pack's gates below): the build boots on its spec, every ability the
    -- character knows is mapped, the casts priced on the true state.
    it("Elemental: boots on its spec, and maps every ability the character knows", function()
        local C = sw.Elemental
        local H = headless.new({ character = C.character() })
        assert.are.same({}, H.loadErrors)
        local unmapped = {}
        for key, a in pairs(H.Hekili.Class.abilities) do
            if type(key) == "string" and a.key == key and a.id and H.ctl.known[a.id] and not sw.MAP[key] then
                unmapped[#unmapped + 1] = key
            end
        end
        table.sort(unmapped)
        assert.are.same({}, unmapped)
        -- the dominant tree picks the spec: settled in the event frame's own OnUpdate (loop_mage_spec.lua's reason)
        for _, f in ipairs(H.frames) do
            local u = f.__scripts.OnUpdate
            if u and debug.getinfo(u, "S").source:find("Engine/Sim/Events.lua", 1, true) then
                for _ = 1, 2 do
                    u(f, 0.016)
                end
            end
        end
        assert.are.equal(C.SPEC, H.Hekili.State.spec.id)
        assert.is_false(pcall(C.resolve, "not_an_ability", H))
        -- the top ranks with Convection 5/5 and Elemental Alacrity 3/3
        local got = {}
        for _, key in ipairs({ "lightning_bolt", "chain_lightning", "lava_burst" }) do
            local p = C.resolve(key, H)
            got[#got + 1] = { p.spell, p.cost, p.cast, p.cooldown }
        end
        assert.are.same({
            { 15208, 220 * 0.9, 2, 0 },
            { 10605, 485 * 0.9, 1.5, 6 },
            { 1326047, 265 * 0.9, 2, 10 },
        }, got)
        assert.is_true(#C.usable(H) > 0)
        assert.are.same({}, H.errors)
    end)

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
