-- tests/Forever/loop_warrior_spec.lua (headless loop design §5, §7, §9): stock Hekili headless as a level 60 Arms
-- Warrior (tests/Forever/helpers/warrior_world.lua) against the harness's world.
local headless = require("Virtual.harness.headless")
local loop = require("Virtual.harness.loop")
local ww = require("Forever.helpers.warrior_world")

describe("headless Arms", function()
    it("boots the Arms character: three entries out of combat with a target, no error, no unlisted nil read", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert.are.equal(ww.SPEC, H.Hekili.State.spec.id)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        local q = H.ns.UI.Displays.Primary.Recommendations
        for i = 1, 3 do
            assert.is_table(H.Hekili.Class.abilities[q[i].actionName], tostring(q[i].actionName))
        end
        assert.are.same({}, H.errors)
        assert.are.same({}, headless.unexpected(H, "run"))
    end)
end)

describe("the Warrior world mapping", function()
    local H
    setup(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
    end)

    it("maps every ability the Arms pack can recommend that the character knows; an unmapped key fails", function()
        local unmapped = {}
        for _, list in pairs(H.Hekili.DB.profile.packs[ww.PACK].lists) do
            for _, entry in ipairs(list) do
                local a = entry.action and H.Hekili.Class.abilities[entry.action]
                if a and a.id and H.ctl.known[a.id] and not ww.MAP[entry.action] then
                    unmapped[#unmapped + 1] = entry.action
                end
            end
        end
        assert.are.same({}, unmapped)
        local ok, err = pcall(ww.resolve, "not_an_ability", H)
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("unmapped key not_an_ability", 1, true))
    end)

    it("maps every ability of the Arms, Fury and Protection packs, known or not", function()
        local unmapped, packs = {}, {}
        for _, name in ipairs({ "Arms", "Fury", "Protection" }) do
            local pack = H.Hekili.DB.profile.packs[name]
            packs[#packs + 1] = pack ~= nil
            for _, list in pairs(pack and pack.lists or {}) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    if a and (a.id or 0) > 0 and not ww.MAP[entry.action] then -- a spell (internal handlers: id <= 0)
                        unmapped[#unmapped + 1] = name .. ":" .. entry.action
                    end
                end
            end
        end
        assert.are.same({ true, true, true }, packs)
        table.sort(unmapped)
        assert.are.same({}, unmapped)
    end)

    it("knows Recklessness and Slam; Slam resolves with the class file's cast time", function()
        local a = H.Hekili.Class.abilities
        assert.is_truthy(H.ctl.known[a.recklessness.id])
        assert.is_truthy(H.ctl.known[a.slam.id])
        assert.is_falsy(H.ctl.known[a.slam.copy[#a.slam.copy]]) -- Improved Slam's override: not this build
        local slam = ww.resolve("slam", H)
        assert.are.same({ a.slam.cast, a.slam.cooldown }, { slam.cast, slam.cooldown })
        assert.is_true(slam.cast > 0)
    end)

    it("keeps the rage the class file's swap_stance keeps on a stance swap", function()
        local s = H.Hekili.State
        s.rage.current, s.rage.actual = 100, 100
        s.swap_stance("berserker_stance") -- the booted class file, on the character's talents and spells
        local keep = s.rage.actual
        assert.are.equal(85, keep) -- Forever's Tactical Mastery passive 10, the talent's 5 ranks 15 each
        local W = { t = 0 }
        local e = { power = 100, form = 1 }
        function W.setForm(x, f)
            x.form = f
        end
        function W.gain(x, n)
            x.power = x.power + n
        end
        ww.resolve("berserker_stance", H).effect(W, e)
        assert.are.same({ keep, ww.FORM.berserker_stance }, { e.power, e.form })
    end)

    it(
        "resolves a press from the class file: cost, cooldown and GCD as the state has them; a strike on the next swing",
        function()
            local ms, hs = ww.resolve("mortal_strike", H), ww.resolve("heroic_strike", H)
            local a = H.Hekili.Class.abilities
            assert.are.same({ -- the rank the client casts, the highest known; every rank answers its cooldown
                H.ns.VirtualState.KnownID(a.mortal_strike.id),
                H.Hekili.State.action.mortal_strike.cost,
                a.mortal_strike.cooldown,
                false,
            }, { ms.spell, ms.cost, ms.cooldown, ms.offGcd })
            assert.are.equal(a.mortal_strike.id, ms.ids[1])
            assert.are.equal(ms.spell, ms.ids[#ms.ids])
            assert.are.same(
                { true, true, H.Hekili.State.action.heroic_strike.cost },
                { hs.onNextSwing, hs.offGcd, hs.cost }
            )
        end
    )

    it(
        "answers usability from the true world: Execute under 20% health, Overpower after a dodge, a stance's own",
        function()
            local answers, by = ww.usable(H), {}
            for _, u in ipairs(answers) do
                by[u[1]] = u[2]
            end
            local a = H.Hekili.Class.abilities
            local mob = { health = 100, healthMax = 100 }
            local W, e = { t = 10 }, { form = ww.FORM.battle_stance, target = mob, avoidAt = {} }
            assert.is_false(by[a.execute.id](W, e, 100))
            mob.health = 19
            assert.is_true(by[a.execute.id](W, e, 100))
            assert.is_false(by[a.execute.id](W, e, 5)) -- short of its cost
            assert.is_false(by[a.overpower.id](W, e, 100))
            e.avoidAt.DODGE = 8
            assert.is_true(by[a.overpower.id](W, e, 100))
            assert.is_false(by[a.whirlwind.id](W, e, 100)) -- Berserker Stance's
            e.form = ww.FORM.berserker_stance
            assert.is_true(by[a.whirlwind.id](W, e, 100))
        end
    )
end)

describe("the headless Arms loop", function()
    local L
    setup(function()
        L = loop.new(ww)
    end)

    it("shows the precombat queue checkpoint C1 compares: no Battle Shout, a hostile target, no rage", function()
        local first
        loop.run(L, 1, {
            duration = 0,
            react = -1, -- watch, press nothing
            on = function(_, steps, t)
                if not first and steps[1].q.name[1] then
                    local q = steps[1].q
                    first = { t, q.name[1], q.name[2], q.name[3] }
                end
            end,
        }, { { H = L.us } })
        print(("\nC1 headless precombat queue at %.1f s: %s %s %s"):format(unpack(first)))
        assert.are.same({ "bloodrage", "battle_shout", "berserker_stance" }, { first[2], first[3], first[4] })
    end)

    it("smoke: one 30 s fight, ours driving, the oracle shadowing and then driving (fast)", function()
        local a, b = loop.fight(L, 1, { duration = 30 })
        for _, r in ipairs({ a, b }) do
            assert.are.same({ 0, 0 }, { r.errors, r.raises })
            assert.are.same({}, r.misses)
            assert.is_true(r.presses > 0)
            assert.are.same({}, r.selfCheck) -- the oracle's belief is the truth at every tick
        end
        assert.are.same({}, L.us.loadErrors)
    end)
end)

-- The gates (headless loop design §5.2; as built: the plan's Deviations 7-8, 14-15). Measured on the plan's replay:
-- 6 fights (in `make check`, about 150 s in all): agreement 0.953, react median 0 / p90 1 / never 0.073, cost refusals
-- 17.1 per 100 (the oracle's 16.4), DPS A/B 0.999 (reported), CPU mean 2.95 ms.
-- 20 fights (`make test-loop`): agreement 0.966, react median 0 / p90 0 / never 0.060, cost refusals 16.5 per 100
-- attempts (the oracle's own 15.8), DPS A/B 0.993, GCD idle 0.742 / 0.739, Sunder Armor up 0.95 / 0.95, flicker
-- 0.69/min, CPU mean 2.70 ms.
-- Report-only: full-rage time (rage never reaches full in these fights) and Demoralizing Shout uptime (the Arms
-- priority keeps it off by default).
local REPORTED = { demoralizing_shout = true }

-- The engine and the first icon, gated at any fight count.
local function gate(m, r, line)
    assert.is_true(r.agreement >= 0.85, line)
    assert.is_true(r.reactMedian <= 1 and r.reactP90 <= 3 and r.never <= 0.08, line)
    assert.is_true((r.per100.gcd or 0) == 0 and (r.per100.cooldown or 0) == 0, line)
    assert.is_true((r.per100.cost or 0) <= (r.per100B.cost or 0) + 3, line)
    assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
    assert.are.same({}, m.misses)
    assert.are.same({}, m.secrets) -- no facade passthrough answered a secret (the traced first fight)
    assert.is_true(r.cpuMean <= 10, line) -- D5: about 4x the measured mean; p99 reported
end

local function solo(n)
    local m = loop.tally(loop.new(ww), n)
    local r, line = loop.summary(m), loop.line(m)
    print("\nArms solo: " .. line)
    gate(m, r, line)
    return r, line
end

-- `make check` runs 6 fights (#slow): DPS A/B is reported there, not gated (per fight its sd is about 0.11).
describe("the headless Arms gates #slow", function()
    it("Arms solo, level 60, one mob, 6 fights of up to 3 minutes: the first icon against the oracle's", function()
        solo(6)
    end)
end)

-- `make test-loop` runs the full 20 (#loop), outside `make check` for its time: the outcome gates too.
describe("the headless Arms gates, 20 fights #loop", function()
    it("Arms solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
        local r, line = solo(20)
        assert.is_true(r.dps >= 0.97, line)
        assert.is_true(r.idleA <= r.idleB + 0.03, line)
        for key, up in pairs(r.upB) do
            if not REPORTED[key] then
                assert.is_true((r.upA[key] or 0) >= up - 0.03, key .. ": " .. line)
            end
        end
        assert.is_true(r.flicker <= 2, line)
    end)
end)

-- The party report (§5.2): reported, engine health gated; `make test-party`, not `make check` (D2).
describe("the headless Arms party report #party", function()
    it("Arms in a party of 5, a melee and a caster on our target, 10 fights: reported", function()
        local m = loop.tally(loop.new(ww), 10, { others = { "melee", "caster" } })
        print("\nArms party: " .. loop.line(m))
        assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
        assert.are.same({}, m.misses)
    end)
end)
