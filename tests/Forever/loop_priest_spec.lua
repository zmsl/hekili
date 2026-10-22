-- tests/Forever/loop_priest_spec.lua (class-completion plan, "The per-pack gate"): the Priest loop worlds
-- (tests/Forever/helpers/priest_world.lua) boot as a level 60 Priest on their spec and map every ability the character
-- knows, its casts and channels resolved; stock Hekili headless in each wowsims.com pack against the harness's world.
-- `make check` runs 3 fights a pack (#slow); `make test-priest` the 20 (#priest), one pack a file
-- (loop_priest_<pack>_spec.lua). Each gate also asserts its flagged (focus) lines ran.
local headless = require("Game.harness.headless")
local scenarios = require("Game.harness.scenarios")
local pack_gate = require("Forever.helpers.pack_gate")
local pw = require("Forever.helpers.priest_world")

-- An instance `H` cycled once (its first polls: the form read, the talents) with the simulation reset on it.
local function settled(H)
    local t = H.ctl.now + 0.1
    assert(headless.cycle(H, t))
    H.ns.VirtualState.Drain(t)
    H.Hekili.State.reset("Primary", true)
    return H
end

describe("the Priest loop worlds", function()
    for _, name in ipairs({ "Shadow", "Smite" }) do
        it(name .. ": boots on its spec, and maps every ability the character knows", function()
            local C = pw[name]
            local H = headless.new({ character = C.character() })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for key, a in pairs(H.Hekili.Class.abilities) do
                if type(key) == "string" and a.key == key and a.id and H.ctl.known[a.id] and not pw.MAP[key] then
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
            assert.is_true(#C.usable(H) > 0)
            assert.are.same({}, H.errors)
        end)
    end

    -- Shadow's presses on the true state: Mind Blast a cast bar at half cost in Shadowform, Mind Flay a channel of three
    -- 1 s ticks, Devouring Plague's cost under Devouring Contagion and Shadowform, Shadow Word: Pain's 24 s.
    it("Shadow: resolves its casts and Mind Flay's channel, and presses them in the world", function()
        local C = pw.Shadow
        local H = settled(headless.new({ character = C.character() }))
        local function resolve(key)
            local p = C.resolve(key, H)
            return { p.cost, p.cast, p.cooldown, p.channel and p.channel.length or false }
        end
        assert.are.same({ 175, 1.5, 5.5, false }, resolve("mind_blast")) -- Improved Mind Blast 5/5
        assert.are.same({ 102.5, 0, 0, 3 }, resolve("mind_flay"))
        assert.are.same({ 246.25, 0, 24, false }, resolve("devouring_plague"))
        assert.are.same({ 170, 0, 18, false }, resolve("shadow_word_death"))
        local W = scenarios.world(setmetatable({ fsr = C.WORLD.fsr }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        us.form = 1 -- in Shadowform (the character's login form)
        local kinds = function(from)
            local out = {}
            for i = from, #W.truth do
                local k = W.truth[i].kind
                if k == "cast" or k == "castStart" or k == "channelStop" then
                    out[#out + 1] = k .. " " .. W.truth[i].t
                end
            end
            return out
        end
        W.t = 1
        assert.is_true(W.press(us, "mind_blast", C.resolve("mind_blast", H)))
        W.run(3)
        W.t = 3
        assert.is_true(W.press(us, "mind_flay", C.resolve("mind_flay", H)))
        W.run(7)
        local ticks = 0
        for _, ev in ipairs(W.truth) do
            ticks = ticks + ((ev.kind == "spell" and ev.src == us and ev.school == 32 and ev.t > 3) and 1 or 0)
        end
        assert.are.same({ { "castStart 1", "cast 2.5", "cast 3", "channelStop 6" }, 3 }, { kinds(1), ticks })
        -- Shadow Word: Pain's landing (a stand-in world whose hit lands): 18 s + 6 s of Improved Shadow Word: Pain 2/2
        local put
        local stub = {
            hit = function()
                return { act = "WOUND" }
            end,
            applyAura = function(_, id, duration)
                put = { id, duration }
            end,
            emit = function() end,
        }
        C.resolve("shadow_word_pain", H).effect(stub, { auras = {}, target = {} })
        assert.are.same({ 589, 24 }, put)
        assert.are.same({}, H.errors)
    end)

    -- Smite's presses: the Mental Agility and Divine Fury talents, Penance's channel (a bolt at its start and two ticks)
    -- and the wand's one shot a wand speed later.
    it("Smite: resolves its casts, Penance's channel and the wand's Shoot", function()
        local C = pw.Smite
        local H = settled(headless.new({ character = C.character() }))
        local function resolve(key)
            local p = C.resolve(key, H)
            return { p.cost, p.cast, p.cooldown, p.channel and p.channel.length or false, p.offGcd }
        end
        assert.are.same({ 252, 2, 0, false, false }, resolve("smite"))
        assert.are.same({ 229.5, 3, 0, false, false }, resolve("holy_fire"))
        assert.are.same({ 385, 0, 12, 2, false }, resolve("penance"))
        assert.are.same({ 247.5, 0, 180, false, true }, resolve("power_infusion"))
        assert.are.same({ 0, 0, 0, 1.2, true }, resolve("shoot"))
        local W = scenarios.world(setmetatable({ fsr = C.WORLD.fsr }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        assert.is_true(W.press(us, "penance", C.resolve("penance", H)))
        W.run(4)
        local bolts = 0
        for _, ev in ipairs(W.truth) do
            bolts = bolts + ((ev.kind == "spell" and ev.src == us and (ev.school == 2 or ev.act ~= "WOUND")) and 1 or 0) -- a miss is school 1
        end
        assert.are.equal(3, bolts)
        W.t = 4
        assert.is_true(W.press(us, "shoot", C.resolve("shoot", H)))
        assert.are.same({ false, "casting" }, { W.press(us, "smite", C.resolve("smite", H)) })
        W.run(5.3)
        local shots = 0
        for _, ev in ipairs(W.truth) do
            shots = shots + ((ev.kind == "spell" and ev.src == us and ev.school == 4) and 1 or 0)
        end
        assert.are.same({ 1, nil }, { shots, us.channel })
        assert.are.same({}, H.errors)
    end)
end)

describe("the headless Priest gates, 3 fights a pack #slow", function()
    for _, name in ipairs({ "Shadow", "Smite" }) do
        it(
            name .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = pack_gate.solo(name, pw[name], 3, nil, "seeds 1-3")
                print(name .. " focus ticks: " .. r.focus)
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)
