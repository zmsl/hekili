-- tests/Forever/loop_warrior_spec.lua (headless loop design §5, §7, §9): stock Hekili headless as a level 60 Arms
-- Warrior (tests/Forever/helpers/warrior_world.lua) against the harness's world.
local headless = require("Game.harness.headless")
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")
local gate = require("Forever.helpers.arms_gate")

describe("headless Arms", function()
    it("boots the Arms character: two entries out of combat with a target, no error, no unlisted nil read", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert.are.equal(ww.SPEC, H.Hekili.State.spec.id)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(out.count >= 2) -- Bloodrage and Battle Shout: no positions, so no Charge (pre_pull_move)
        local q = out.recs
        for i = 1, 2 do
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

    it("maps every ability of the three Warrior packs, known or not (but other races' racials)", function()
        local unmapped, packs = {}, {}
        for _, name in ipairs({ "Arms (wowsims.com)", "Fury (wowsims.com)", "Protection (wowsims.com)" }) do
            local pack = H.Hekili.DB.profile.packs[name]
            packs[#packs + 1] = pack ~= nil
            for _, list in pairs(pack and pack.lists or {}) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    -- a spell (internal handlers: id <= 0) the character's race allows (another race's: known = false)
                    if a and (a.id or 0) > 0 and a.known ~= false and not ww.MAP[entry.action] then
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
                    first = { t, q.name[1], q.name[2], q.name[3] or "none" }
                end
            end,
        }, { { H = L.us } })
        print(("\nC1 headless precombat queue at %.1f s: %s %s %s"):format(unpack(first)))
        assert.are.same({ "bloodrage", "battle_shout", "none" }, { first[2], first[3], first[4] })
    end)

    it(
        "believes Sunder Armor's true stacks on the oracle across two forced presses (a read in the cast's frame)",
        function()
            local H = L.oracle
            local id = H.Hekili.Class.auras.sunder_armor.id
            local VS = H.ns.VirtualState
            local wrong, presses = {}, 0
            loop.run(L, 1, {
                duration = 12,
                react = -1, -- watch: only the forced presses below
                on = function(run, steps, t)
                    local us = run.us
                    local a = us.target and us.target.auras[id]
                    local truth = a and a.expires > t + 1e-6 and a.stacks or nil
                    local belief = select(2, VS.Aura("target", id, steps[1].base + t))
                    if truth ~= belief and presses > 0 then
                        wrong[#wrong + 1] = ("t=%.1f truth %s belief %s"):format(t, tostring(truth), tostring(belief))
                    end
                    if math.abs(t - 4) < 1e-6 or math.abs(t - 6) < 1e-6 then
                        us.power = math.max(us.power, 30)
                        assert.is_true(run.W.press(us, "sunder_armor", ww.resolve("sunder_armor", H)))
                        presses = presses + 1
                    end
                end,
            }, { { H = H, plain = true } })
            assert.are.equal(2, presses)
            assert.are.same({}, wrong)
        end
    )

    it(
        "believes Sunder Armor's true stacks on ours across seven presses: target auras raise in combat; 5 is the cap",
        function()
            local H = L.us
            local id = H.Hekili.Class.auras.sunder_armor.id
            local VS = H.ns.VirtualState
            local wrong, presses = {}, 0
            loop.run(L, 1, {
                duration = 20,
                react = -1, -- watch: only the forced presses below
                on = function(run, steps, t)
                    local us = run.us
                    local a = us.target and us.target.auras[id]
                    local truth = a and a.expires > t + 1e-6 and a.stacks or nil
                    local belief = select(2, VS.Aura("target", id, steps[1].base + t))
                    if truth ~= belief and presses > 0 then
                        wrong[#wrong + 1] = ("t=%.1f truth %s belief %s"):format(t, tostring(truth), tostring(belief))
                    end
                    -- 5, 7, ... 17 s: a press at 4 s meets seed 1's parry of a 1.0 s late swing, which the belief gives the
                    -- cast as its avoid (the attribution gap, central fix 18's report)
                    if t > 4 and t < 18 and math.abs((t - 1) / 2 - math.floor((t - 1) / 2 + 0.5)) < 1e-6 then
                        assert.is_false((pcall(H.api.C_UnitAuras.GetAuraDataByIndex, "target", 1, "HARMFUL")))
                        us.power = math.max(us.power, 30)
                        assert.is_true(run.W.press(us, "sunder_armor", ww.resolve("sunder_armor", H)))
                        presses = presses + 1
                    end
                end,
            }, { { H = H } })
            assert.are.equal(7, presses)
            assert.are.same({}, wrong)
        end
    )

    it("smoke: one 30 s fight, ours driving, the oracle shadowing and then driving (fast)", function()
        local a, b = loop.fight(L, 1, { duration = 30 })
        for _, r in ipairs({ a, b }) do
            assert.are.same({ 0, 0 }, { r.errors, r.raises })
            assert.are.same({}, r.misses)
            assert.is_true(r.presses >= 5 and r.damage > 0, r.presses .. " presses, " .. r.damage .. " damage")
            assert.are.same({}, r.selfCheck) -- the oracle's belief is the truth at every tick
        end
        assert.are.same({}, L.us.loadErrors)
    end)
end)

-- The gates (headless loop design §5.2; the thresholds and their measured values: helpers/arms_gate.lua). `make check`
-- runs 6 fights (#slow) as two files of 3, run in parallel: seeds 1-3 here, 4-6 in loop_warrior_late_spec.lua. Each
-- fight seeds its own world (scenarios.world(o, seed)) and the boot carries nothing between fights, so a half on a fresh
-- boot plays the same fights as the old single 6-fight run.
describe("the headless Arms gates, fights 1-3 #slow", function()
    it("Arms solo, level 60, one mob, fights 1-3 of up to 3 minutes: the first icon against the oracle's", function()
        local r, line = gate.solo(3, nil, "seeds 1-3")
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line) -- review focus 5
    end)
end)

-- `make test-loop` runs the full 20 (#loop), outside `make check` for its time: the outcome gates too.
describe("the headless Arms gates, 20 fights #loop", function()
    it("Arms solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
        local r, line = gate.solo(20)
        assert.is_true(r.never <= 0.08, line)
        -- 0.969 (was 0.975): harness corrected to the measured swing timing (2026-10-22)
        assert.is_true(r.dps >= 0.965, line) -- the old 0.005 margin
        assert.is_true(r.idleA <= r.idleB + 0.03, line)
        for key, up in pairs(r.upB) do
            if not gate.REPORTED[key] then
                assert.is_true((r.upA[key] or 0) >= up - 0.03, key .. ": " .. line)
            end
        end
        assert.is_true(r.flicker <= 2, line)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
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
