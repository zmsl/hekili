-- tests/Forever/loop_warlock_spec.lua (class-completion plan, "The per-pack gate"): the Warlock loop worlds
-- (tests/Forever/helpers/warlock_world.lua) boot as a level 60 Warlock on their spec and map every ability the
-- character knows, its casts and channels resolved; a cast bar, a channel and a DoT's ticks in the world. The solo
-- gates (`Affliction solo:`, `Demonology solo:`, `Destruction solo:`) come with the wowsims.com packs (the next task).
local headless = require("Game.harness.headless")
local scenarios = require("Game.harness.scenarios")
local ww = require("Forever.helpers.warlock_world")

-- The pet's spends in the truth after event `n0`: each fall of its power between two pet events.
local function petSpends(W, n0)
    local out, last = {}, nil
    for i = n0 + 1, #W.truth do
        local ev = W.truth[i]
        if ev.kind == "pet" or ev.kind == "petPower" then
            if last and ev.power < last then
                out[#out + 1] = math.floor(last - ev.power + 0.5)
            end
            last = ev.power
        end
    end
    return out
end

describe("the Warlock loop worlds", function()
    for _, name in ipairs({ "Affliction", "Demonology", "Destruction" }) do
        it(name .. ": boots on its spec, and maps every ability the character knows", function()
            local C = ww[name]
            local H = headless.new({ character = C.character() })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for key, a in pairs(H.Hekili.Class.abilities) do
                if type(key) == "string" and a.key == key and a.id and H.ctl.known[a.id] and not ww.MAP[key] then
                    unmapped[#unmapped + 1] = key
                end
            end
            table.sort(unmapped)
            assert.are.same({}, unmapped)
            -- the dominant tree of the preset build picks the spec: the pick settles in the event frame's own
            -- OnUpdate (Engine/Sim/Events.lua; the harness's cycle does not run it), as spec_choice_spec.lua settles it
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
            -- the channels at their lengths and ticks
            local dl, ds = C.resolve("drain_life", H), C.resolve("drain_soul", H)
            assert.are.same({ 5, 1, 15, 3 }, { dl.channel.length, dl.channel.tick, ds.channel.length, ds.channel.tick })
            -- a cast press: its top rank's cost and cast time on the true state (Bane 5/5 in every build; Cataclysm
            -- 3/3 in Destruction's)
            local p = C.resolve("shadow_bolt", H)
            assert.are.same({ name == "Destruction" and 342 or 380, 2.5, 0 }, { p.cost, p.cast, p.cooldown })
            assert.is_true(#C.usable(H) > 0)
            assert.are.same({}, H.errors)
        end)
    end

    -- The presses in the world: Corruption's cast bar and its ticks on the target, then Wrack's channel and its debuff.
    it("Affliction: casts Corruption as a cast bar, ticks it, and channels Wrack with its debuff", function()
        local C = ww.Affliction
        local H = headless.new({ character = C.character() })
        local W = scenarios.world(setmetatable({ fsr = C.WORLD.fsr, power = 5000 }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        local cor = C.resolve("corruption", H)
        assert.are.same({ 340, 0.8 }, { cor.cost, math.floor(cor.cast * 1000 + 0.5) / 1000 }) -- Improved Corruption 3/3 of 5: 2 - 1.2
        assert.is_true(W.press(us, "corruption", cor))
        W.run(1.8)
        local cast = false
        for _, ev in ipairs(W.truth) do
            cast = cast or (ev.kind == "cast" and ev.src == us and math.abs(ev.t - 1.8) < 1e-9)
        end
        assert.is_true(cast)
        local landed = us.target.auras[172] ~= nil -- a missed one (the spell table) leaves none
        W.run(20)
        local ticks = 0
        for _, ev in ipairs(W.truth) do
            ticks = ticks + ((ev.kind == "tick" and ev.src == us and ev.school == 32) and 1 or 0)
        end
        assert.are.equal(landed and 6 or 0, ticks) -- every 3 s for its 18 s, the last at the expiry
        local n0 = #W.truth
        W.t = W.t + 1
        local wr = C.resolve("wrack", H)
        assert.are.same({ 200, 6, 1 }, { wr.cost, wr.channel.length, wr.channel.tick })
        assert.is_true(W.press(us, "wrack", wr))
        assert.is_truthy(us.target.auras[1316697]) -- the channel's debuff
        W.run(W.t + 6.5)
        local ticks, stop = 0, false
        for i = n0 + 1, #W.truth do
            local ev = W.truth[i]
            ticks = ticks + ((ev.kind == "tick" and ev.src == us) and 1 or 0)
            stop = stop or ev.kind == "channelStop"
        end
        assert.are.same({ 6, true }, { ticks, stop })
    end)

    -- Fix 27's world: the Soul Shards in the bags (wowsims's 32), the demon and its mana, the Spirit Life Tap reads.
    it(
        "declares the shards, the demon and Spirit; the shard spells take a reagent, the summons and Sacrifice the pet",
        function()
            for _, name in ipairs({ "Affliction", "Demonology", "Destruction" }) do
                local C = ww[name]
                assert.are.same({ [6265] = 32 }, C.WORLD.bags, name)
                assert.are.same({ [5] = 221 }, C.WORLD.stats, name)
                local pet = C.WORLD.pet
                -- wowsims's logs at 60: the Imp 2180 mana, 85.2 mp5; the Succubus 1871, 28.4 mp5
                local want = name == "Demonology" and { 0, 2180, 2180, 17.04, 2, false }
                    or { 0, 1871, 1871, 5.68, 2, false }
                assert.are.same(want, { pet.pt, pet.max, pet.power, pet.regen, pet.tick, pet.up }, name)
            end
            local C = ww.Destruction
            local H = headless.new({ character = C.character() })
            for _, key in ipairs({ "shadowburn", "soul_fire", "summon_succubus", "summon_felhunter" }) do
                assert.are.same({ 6265, 1 }, C.resolve(key, H).reagent, key)
            end
            local imp = C.resolve("summon_imp", H)
            assert.are.same({ true, "summon" }, { imp.reagent == nil, imp.pet })
            assert.are.equal("dismiss", C.resolve("demonic_sacrifice", H).pet)
        end
    )

    it("Destruction: summons the Succubus for a shard; its Lash of Pain spends its mana", function()
        local C = ww.Destruction
        local H = headless.new({ character = C.character() })
        local W = scenarios.world(setmetatable({ power = 5000 }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.run(1) -- the pull
        local su = C.resolve("summon_succubus", H)
        assert.is_true(W.press(us, "summon_succubus", su))
        W.run(1 + su.cast + 0.05)
        assert.are.same({ 31, true }, { us.bags[6265], us.pet.up })
        local n0 = #W.truth
        W.run(W.t + 25)
        assert.are.same({ 160, 160 }, petSpends(W, n0)) -- Lash of Pain's 160, 12 s apart
        assert.are.same({}, H.errors)
    end)

    it("Demonology: the Imp keeps the sacrificed Succubus's effect (Demonic Pact); Sacrifice takes the Imp", function()
        local C = ww.Demonology
        local H = headless.new({ character = C.character() })
        local W = scenarios.world(setmetatable({ power = 5000 }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.run(1) -- the pull
        assert.is_truthy(us.auras[18791]) -- the build's sacrificed Succubus: Touch of Fire from the pull
        assert.is_false(W.press(us, "demonic_sacrifice", C.resolve("demonic_sacrifice", H))) -- no demon out
        local imp = C.resolve("summon_imp", H)
        assert.is_true(W.press(us, "summon_imp", imp))
        W.run(1 + imp.cast + 0.05)
        assert.are.same({ 32, true, true }, { us.bags[6265], us.pet.up, us.auras[18791] ~= nil })
        local n0 = #W.truth
        W.run(W.t + 5)
        assert.are.same({ 115, 115 }, petSpends(W, n0)) -- Firebolt's 115 a 2 s cast
        W.t = W.t + 1.5
        assert.is_true(W.press(us, "demonic_sacrifice", C.resolve("demonic_sacrifice", H)))
        W.run(W.t + 0.1)
        assert.are.same({ false, true, false }, { us.pet.up, us.auras[18789] ~= nil, us.auras[18791] ~= nil })
        assert.are.same({}, H.errors)
    end)
end)
