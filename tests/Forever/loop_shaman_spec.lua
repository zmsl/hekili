-- tests/Forever/loop_shaman_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Shaman in each pack (tests/Forever/helpers/shaman_world.lua) against the harness's world; the mob swings at us
-- (Lightning Shield's charges spent by its hits), the world keeps the totem slots (W.summonTotem). `make check` runs 3
-- fights a pack (#slow); `make test-shaman` the 20 (#shaman: loop_shaman_enhancement_spec.lua and
-- loop_shaman_elemental_spec.lua). Each gate also asserts its flagged lines ran (review focus 5).
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local sw = require("Forever.helpers.shaman_world")

local PACKS = { "Enhancement", "Elemental" }

describe("the Shaman loop worlds", function()
    -- Each world's pool and regen are its wowsims log's (OtherID 2 regen ticks, 0.1 s apart): the max mana, the casting
    -- tick without and with Mana Spring Totem's 5 a second (Tag 1) and the tick outside the five-second rule (Tag 2)
    for _, key in ipairs(PACKS) do
        it(key .. ": the pool and the five-second rule's rates are its wowsims log's", function()
            local Wd = sw[key].WORLD
            local f = Wd.fsr[0]
            local log = assert(io.open("tests/Forever/wowsims/shaman_" .. key:lower() .. ".log")):read("*a")
            local spirit, mp5, totem = f[1], f[2], f.auras[10494].mp5
            assert.are.equal(Wd.max, tonumber(log:match("of (%d+) total")))
            for _, t in ipairs({ { 1, mp5 }, { 1, mp5 + totem }, { 2, spirit + mp5 + totem } }) do
                local row = ("Gained %.3f mana from {OtherID: 2, Tag: %d}"):format(t[2] / 10, t[1])
                assert.is_truthy(log:find(row, 1, true), row)
            end
        end)
    end

    -- wowsims e4ef929e54: Maelstrom Weapon's rate is its rank's 6..10 a minute (curve 408498), and our Windfury Totem
    -- standing rolls a weapon strike (20%, a 0.1 s ICD) on a landed main-hand swing, which stacks no Maelstrom Weapon
    it(
        "Enhancement: a landed main-hand swing rolls Maelstrom Weapon by rank and our Windfury Totem's strike",
        function()
            local us = { weapons = { { 180, 260, 3.6 } }, auras = {} }
            local W = { t = 10, rolls = {}, hits = 0, slot = nil }
            W.rng = {
                chance = function(p)
                    W.rolls[#W.rolls + 1] = p
                    return false
                end,
            }
            W.totem = function(_, slot)
                return slot == 4 and W.slot or nil
            end
            W.hit = function()
                W.hits = W.hits + 1
                return { act = "WOUND" }
            end
            sw.Enhancement.WORLD.script(W, us)
            us.target = {}
            us.landed(W, "WOUND", 1) -- no totem: the Maelstrom Weapon roll only, 10 a minute at 5/5 on a 3.6 s weapon
            assert.are.same({ 0.6 }, W.rolls)
            W.rolls, W.slot = {}, { spell = 10614 } -- Windfury Totem rank 3 in the air slot
            us.landed(W, "WOUND", 2) -- the off hand: no strike roll
            us.landed(W, "DODGE", 1) -- not landed: no roll at all
            assert.are.same({ 0.6 }, W.rolls)
            W.rolls = {}
            W.rng.chance = function(p)
                W.rolls[#W.rolls + 1] = p
                return p == 0.2 -- the strike procs; Maelstrom Weapon does not
            end
            us.landed(W, "WOUND", 1)
            us.landed(W, "WOUND", 1) -- the same instant: inside the 0.1 s ICD
            assert.are.same({ 0.6, 0.2, 0.6 }, W.rolls)
            assert.are.equal(1, W.hits)
            assert.are.same({}, us.auras) -- the strike stacked no Maelstrom Weapon
            W.t, W.slot = 10.1, { spell = 25359 } -- Grace of Air Totem in the air slot: no strike
            W.rolls = {}
            us.landed(W, "WOUND", 1)
            assert.are.same({ 0.6 }, W.rolls)
        end
    )

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

    -- A press is priced by the world's us the loop passes (L1233): its auras even once its stop has run (the fight's
    -- last tick); a resolve with no world reads no aura.
    it("Enhancement: prices Lightning Bolt from the passed world's Maelstrom Weapon, stopped or not", function()
        local C = sw.Enhancement
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local us = { auras = { [408505] = { stacks = 5, expires = 1e9 } }, stopped = true }
        assert.are.same({ 0, 0 }, {
            C.resolve("lightning_bolt", H, us).cost,
            C.resolve("lightning_bolt", H, us).cast,
        })
        assert.are.equal(220, C.resolve("lightning_bolt", H).cost)
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
        for _, key in ipairs({ "lightning_bolt", "chain_lightning" }) do
            local p = C.resolve(key, H)
            got[#got + 1] = { p.spell, p.cost, p.cast, p.cooldown }
        end
        assert.are.same({
            { 15208, 220 * 0.9, 2, 0 },
            { 10605, 495 * 0.9, 1.5, 6 },
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
