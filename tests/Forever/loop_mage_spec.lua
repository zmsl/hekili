-- tests/Forever/loop_mage_spec.lua (class-completion plan, "The per-pack gate"): the Mage loop worlds
-- (tests/Forever/helpers/mage_world.lua) boot as a level 60 Mage on their spec and map every ability the character
-- knows, its casts and channels resolved; stock Hekili headless in each wowsims.com pack against the harness's world.
-- `make check` runs 3 fights a pack (#slow); `make test-mage` the 20 (#mage), one pack a file
-- (loop_mage_<pack>_spec.lua). Each gate also asserts its flagged (focus) lines ran.
local headless = require("Game.harness.headless")
local scenarios = require("Game.harness.scenarios")
local pack_gate = require("Forever.helpers.pack_gate")
local mw = require("Forever.helpers.mage_world")

describe("the Mage loop worlds", function()
    for _, name in ipairs({ "Arcane", "Fire", "Frostfire", "Frost" }) do
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
            -- the channels: Evocation 8 s a tick a second (no tick effect: its mana is the regen's), Arcane Missiles at
            -- its rank
            local evo, am = C.resolve("evocation", H), C.resolve("arcane_missiles", H)
            assert.are.same({ 8, 1, false, 5, 1, true, false }, {
                evo.channel.length,
                evo.channel.tick,
                type(evo.channel.effect) == "function",
                am.channel.length,
                am.channel.tick,
                type(am.channel.effect) == "function",
                evo.clip or false, -- no channel running
            })
            -- a cast press: its top rank's cost and cast time on the true state
            local key = ({ Arcane = "arcane_wrath", Frost = "frostbolt" })[name] or "fireball"
            local p = C.resolve(key, H) -- a cast bar (UNIT_SPELLCAST_START at the press: W.press with a cast time)
            assert.are.same( -- Fireball rank 11 (the trainer's: no book rank), Improved Fireball 5/5: 3.5 - 0.5;
                -- Frostbolt rank 10 (no book rank), Frost Channeling 1/3 and Improved Frostbolt 5/5: 260 x 0.95, 3 - 0.5
                ({ Arcane = { 395, 3.5, 6 }, Frost = { 247, 2.5, 0 } })[name] or { 395, 3, 0 },
                { p.cost, p.cast, p.cooldown }
            )
            assert.is_true(#C.usable(H) > 0)
            assert.are.same({}, H.errors)
            -- the client's static spell ranges (DB2 70707), so a travelling cast's flight window is its real one: a
            -- Fireball crit 0.83 s out (20 yd) lands inside 35 / 24 s, never past a 5 yd default's 0.21 s
            local info = H.api.C_Spell.GetSpellInfo
            assert.are.same({ 35, 20, 0 }, { info(10151).maxRange, info(10199).maxRange, info(12051).maxRange })
        end)
    end

    -- Each damage spell's landed row carries its own school, the class file's declared one, so its ticket takes it: a
    -- frost spell's 16 (an arcane 64 left Frostbolt's ticket open for another source's avoid to pay; inv crowd-drops F1),
    -- a fire one's 4.
    it("Frost: a frost spell's row is school 16, a fire one's 4", function()
        local C = mw.Frost
        local H = headless.new({ character = C.character() })
        local W = scenarios.world(C.WORLD, 1)
        local us = W.ents[1]
        local got = {}
        for i, key in ipairs({ "frostbolt", "cone_of_cold", "ice_lance", "fireball" }) do
            local n = #W.truth
            W.t = 10 * i
            assert.is_true(W.press(us, key, C.resolve(key, H)))
            W.run(10 * i + 5)
            for j = n + 1, #W.truth do
                local ev = W.truth[j]
                if ev.kind == "spell" and ev.src == us and ev.act == "WOUND" then
                    got[key] = ev.school
                end
            end
        end
        assert.are.same({ frostbolt = 16, cone_of_cold = 16, ice_lance = 16, fireball = 4 }, got)
    end)

    -- The presses in the world: a cast bar (castStart at the press, the cast at its end) and Evocation's channel (its
    -- mana the regen's while its aura is up, stopped at its end; a later press with `clip` cuts it).
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
        assert.are.same({ "cast 5" }, kinds(n0 + 1)) -- a channel: its cast at the start, still running at 8
        -- 3 s inside the five-second window at 16x the spirit regen, all of it while casting (the world's 12051 entry:
        -- 466.08 a second, wowsims's), on the regen's 0.1 s tick
        local gained = W.res(us, 0) - p0
        assert.is_true(math.abs(3 * 16 * 29.13 - gained) < 1e-6, tostring(gained))
        assert.is_truthy(us.auras[12051]) -- Evocation's buff for the channel
        local b = C.resolve("arcane_blast", H)
        b.clip = true
        assert.is_true(W.press(us, "arcane_blast", b))
        assert.is_nil(us.channel)
        assert.is_nil(us.auras[12051]) -- the clip ends it with the channel
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
            missiles = missiles
                + ((ev.kind == "spell" and ev.src == us and (ev.school == 64 or ev.act ~= "WOUND")) and 1 or 0) -- a miss is school 1
        end
        assert.are.same({ 5, { "cast 12", "channelStop 17" } }, { missiles, kinds(n1 + 1) })
    end)

    -- wowsims's interruptIf: while the oracle's belief channels Evocation at 99% mana or more, every resolved press
    -- clips it; below that, none does.
    -- An Arcane instance and a world of its own, and upTo(t): the observer's stream (of the world run so far: one
    -- call) to world time `t` into the instance, so its belief is the world's.
    local function driven()
        local observer = require("Game.harness.observer")
        local drive = require("Game.harness.drive")
        local C = mw.Arcane
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local W = scenarios.world(setmetatable({ fsr = C.WORLD.fsr }, { __index = C.WORLD }), 1)
        local base = H.ctl.now + 1 -- the instance's clock at the world's 0
        local k = { gcdSpell = H.ns.VirtualStateInternal.GCD_SPELL, powerType = 0, powerToken = "MANA", plain = true }
        local s, fired = nil, 0
        local function upTo(t)
            s = s or observer.observe(W, setmetatable(k, { __index = observer.DEFAULTS }))
            while fired < s.n and s.t[fired + 1] <= t do
                fired = fired + 1
                local i, ev = fired, s.ev[fired]
                H.ctl.now = base + s.t[i]
                if ev:byte(1) == 64 then -- the drive's answers are in the world's clock
                    local a1, a2 = s.a1[i], s.a2[i]
                    if ev == "@casting" or ev == "@channel" then
                        a1, a2 = a1 and a1 + base * 1000, a2 and a2 + base * 1000
                    end
                    drive.op({}, H.ctl, ev, a1, a2, s.a3[i], s.a4[i], s.a5[i])
                else
                    H.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
                end
            end
            assert(headless.cycle(H, base + t))
            H.ns.VirtualState.Drain(base + t)
        end
        assert(headless.cycle(H, base))
        return C, H, W, W.ents[1], upTo
    end

    it("Arcane: resolves `clip` while the belief channels Evocation at 99% mana or more", function()
        local C, H, W, us, upTo = driven()
        assert.is_false(C.resolve("arcane_blast", H).clip or false) -- nothing channelling
        W.t = 1
        assert.is_true(W.press(us, "evocation", C.resolve("evocation", H)))
        W.run(4)
        upTo(3)
        assert.is_true(H.ns.VirtualState.Power(0, H.ctl.now).est >= 0.99 * 6678) -- the Arcane pool
        assert.is_true(C.resolve("arcane_blast", H).clip) -- full: any press clips it
    end)

    -- The game takes a cast's cost when it completes, with the auras up then (owner, L1383): Arcane Wrath pressed under
    -- Arcane Power is checked at its x1.3 price but lands after Arcane Power ends and pays its own (the L1375 trace).
    it("Arcane: charges a cast bar's cost at its landing, with the auras up then", function()
        local C, H, W, us, upTo = driven()
        W.t = 1
        assert.is_true(W.press(us, "arcane_power", C.resolve("arcane_power", H)))
        local ends = us.auras[H.Hekili.Class.auras.arcane_power.id].expires
        local press = ends - 1 -- the 3.5 s cast lands 2.5 s after Arcane Power ends
        W.run(press)
        upTo(press)
        local wrath = C.resolve("arcane_wrath", H) -- the belief's Arcane Power prices the press
        assert.are.same({ 395 * 1.3, 3.5 }, { wrath.cost, wrath.cast })
        W.t = press
        assert.is_true(W.press(us, "arcane_wrath", wrath))
        W.run(press + 4)
        local paid
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" and ev.src == us and ev.spell == wrath.spell then
                paid = { ev.t, ev.cost }
            end
        end
        assert.are.same({ press + 3.5, 395 }, paid)
    end)
end)

describe("the headless Mage gates, 3 fights a pack #slow", function()
    for _, name in ipairs({ "Arcane", "Fire", "Frostfire", "Frost" }) do
        it(
            name .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = pack_gate.solo(name, mw[name], 3, nil, "seeds 1-3")
                print(name .. " focus ticks: " .. r.focus)
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)
