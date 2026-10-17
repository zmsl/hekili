-- tests/Forever/loop_warrior_spec.lua (headless loop design §5, §7, §9): stock Hekili headless as a level 60 Arms
-- Warrior (tests/Forever/helpers/warrior_world.lua) against the harness's world.
local headless = require("Virtual.harness.headless")
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
        assert.is_true(keep > 0 and keep < 100)
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
            assert.are.same(
                { a.mortal_strike.id, H.Hekili.State.action.mortal_strike.cost, a.mortal_strike.cooldown, false },
                { ms.spell, ms.cost, ms.cooldown, ms.offGcd }
            )
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
