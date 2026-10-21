-- tests/Forever/loop_mage_spec.lua (class-completion plan, "The per-pack gate"): the Mage loop worlds
-- (tests/Forever/helpers/mage_world.lua) boot as a level 60 Mage on their spec and map every ability the character
-- knows, its casts and channels resolved. The solo gates (`Arcane solo:`, `Fire solo:`) come with the wowsims.com packs
-- (the next task).
local headless = require("Game.harness.headless")
local scenarios = require("Game.harness.scenarios")
local mw = require("Forever.helpers.mage_world")

describe("the Mage loop worlds", function()
    for _, name in ipairs({ "Arcane", "Fire" }) do
        it(name .. ": boots on its spec, and maps every ability the character knows", function()
            local C = mw[name]
            local H = headless.new({ character = C.character() })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for key, a in pairs(H.Hekili.Class.abilities) do
                if type(key) == "string" and a.key == key and a.id and H.ctl.known[a.id] and not mw.MAP[key] then
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
            -- the channels: Evocation 8 s a tick a second (its mana each tick's effect), Arcane Missiles at its rank
            local evo, am = C.resolve("evocation", H), C.resolve("arcane_missiles", H)
            assert.are.same({ 8, 1, true, 5, 1, true, false }, {
                evo.channel.length,
                evo.channel.tick,
                type(evo.channel.effect) == "function",
                am.channel.length,
                am.channel.tick,
                type(am.channel.effect) == "function",
                evo.clip or false, -- no channel running
            })
            -- a cast press: its top rank's cost and cast time on the true state
            local key = name == "Arcane" and "arcane_wrath" or "fireball"
            local p = C.resolve(key, H) -- a cast bar (UNIT_SPELLCAST_START at the press: W.press with a cast time)
            assert.are.same(
                name == "Arcane" and { 395, 3.5, 6 } or { 410, 3, 0 }, -- Improved Fireball 5/5: 3.5 - 0.5
                { p.cost, p.cast, p.cooldown }
            )
            assert.is_true(#C.usable(H) > 0)
            assert.are.same({}, H.errors)
        end)
    end

    -- The presses in the world: a cast bar (castStart at the press, the cast at its end) and Evocation's channel (its
    -- mana each tick, stopped at its end; a later press with `clip` cuts it).
    it("Arcane: casts Arcane Wrath as a cast bar and channels Evocation's mana, clipped by a `clip` press", function()
        local C = mw.Arcane
        local H = headless.new({ character = C.character() })
        local W = scenarios.world(setmetatable({ fsr = C.WORLD.fsr, power = 3000 }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        local wrath = C.resolve("arcane_wrath", H)
        assert.is_true(W.press(us, "arcane_wrath", wrath))
        local start = W.truth[#W.truth]
        assert.are.same({ "castStart", 4.5 }, { start.kind, start.ends })
        W.run(5)
        local function kinds(from)
            local out = {}
            for i = from, #W.truth do
                local k = W.truth[i].kind
                if k == "cast" or k == "castStart" or k == "channelStop" then
                    out[#out + 1] = k .. " " .. W.truth[i].t
                end
            end
            return out
        end
        assert.are.same({ "castStart 1", "cast 4.5" }, kinds(1))
        local n0, p0 = #W.truth, W.res(us, 0)
        W.t = 5
        assert.is_true(W.press(us, "evocation", C.resolve("evocation", H)))
        W.run(8)
        local gained = 0
        for i = n0 + 1, #W.truth do
            local ev = W.truth[i]
            if ev.kind == "gain" and ev.src == us and ev.pt == 0 then
                gained = gained + (ev.rage or 0)
            end
        end
        assert.are.same({ "cast 5" }, kinds(n0 + 1)) -- a channel: its cast at the start, still running at 8
        assert.are.equal(3 * 16 * 28, gained) -- three ticks inside the five-second window: 16x the spirit part each
        assert.is_true(W.res(us, 0) > p0)
        local b = C.resolve("arcane_blast", H)
        b.clip = true
        assert.is_true(W.press(us, "arcane_blast", b))
        assert.is_nil(us.channel)
        assert.are.same({ "cast 5", "channelStop 8", "castStart 8" }, kinds(n0 + 1))
        -- Arcane Missiles: a missile a second over its 5 s, each its own spell hit (or miss)
        W.run(12)
        local n1 = #W.truth
        W.t = 12
        assert.is_true(W.press(us, "arcane_missiles", C.resolve("arcane_missiles", H)))
        W.run(20)
        local missiles = 0
        for i = n1 + 1, #W.truth do
            local ev = W.truth[i]
            missiles = missiles + ((ev.kind == "spell" and ev.src == us and ev.school == 64) and 1 or 0)
        end
        assert.are.same({ 5, { "cast 12", "channelStop 17" } }, { missiles, kinds(n1 + 1) })
    end)
end)
