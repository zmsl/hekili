-- tests/Game/harness/replay_spec.lua (wowsims packs plan, Task 3): the wowsims log parser and the log-driven world on
-- the 30-line fixture (fixtures/wowsims_test.log, invented IDs), each of the plan's Review Focus lies pinned. The class
-- data is a stand-in H (replay.new reads only H.Hekili.Class).
local replay = require("Game.harness.replay")

local function text()
    local f = assert(io.open("tests/Game/harness/fixtures/wowsims_test.log", "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

-- The stand-in class data: ability keys by rank IDs, aura durations.
local H = {
    Hekili = {
        Class = {
            abilities = {
                strike = { key = "strike", id = 900001, cooldown = 6, gcd = "spell" },
                shout = { key = "shout", id = 900002, gcd = "spell" },
                surge = { key = "surge", id = 900003, cooldown = 30, gcd = "off" },
                echo = { key = "echo", id = 900004, gcd = "off" },
                stance_a = { key = "stance_a", id = 900010, gcd = "off" },
                stance_b = { key = "stance_b", id = 900011, gcd = "off" },
            },
            auras = {
                shout = { id = 900002, duration = 120 },
                mark = { id = 900030, duration = 12, max_stack = 5 },
                window = { id = 900020, duration = 5 },
            },
        },
    },
}
local O = { forms = { 900010, 900011 }, hidden = { [900020] = true }, procs = { [900004] = true } }
local WO = { level = 60, max = 100, pt = 1, weapons = { { 100, 150, 3.6 } } }

local function at(W, t) -- the world run to world time `t`
    W.run(t)
    return W
end

describe("the wowsims log parser", function()
    local p = replay.parse(text())

    it("reads the header: pin, spec, seed, duration, target level, talents with their trees", function()
        local h = p.header
        assert.are.same(
            { "0123456789abcdef0123456789abcdef01234567", "test_spec", 101, 10, 63 },
            { h.pin, h.spec, h.seed, h.duration, h.targetLevel }
        )
        assert.are.same({ { 900100, 2, 2 }, { 900101, 1, 1 }, { 900102, 3, 2 } }, h.talents)
    end)

    it("reads casts with their cast time and GCD, powers, auras, stacks and outcomes", function()
        local kinds = {}
        for _, e in ipairs(p.ev) do
            kinds[e.kind] = (kinds[e.kind] or 0) + 1
        end
        assert.are.same({ casting = 6, completed = 8, power = 5, aura = 8, stacks = 2, hit = 4 }, kinds)
        local c = p.ev[2]
        assert.are.same({ "casting", -2, 900010, 0, 0 }, { c.kind, c.t, c.id, c.cast, c.gcd })
        local hit = p.ev[12]
        assert.are.same(
            { "hit", "swing", 1, "WOUND", "", 100 },
            { hit.kind, hit.what, hit.hand, hit.act, hit.flag, hit.amount }
        )
        local tick
        for _, e in ipairs(p.ev) do
            if e.kind == "hit" and e.what == "tick" then
                tick = e
            end
        end
        assert.are.same({ 900030, 20 }, { tick.id, tick.amount })
    end)
end)

describe("the replay world", function()
    it("maps casts to keys and decisions: on-GCD flagged, procs neither decisions nor casts", function()
        local R = replay.new(text(), H, O)
        local keys, gcd = {}, {}
        for i, d in ipairs(R.decisions) do
            keys[i], gcd[i] = d.key, d.gcd
        end
        assert.are.same({ "stance_a", "shout", "strike", "surge", "strike" }, keys)
        assert.are.same({ false, true, true, false, true }, gcd)
        -- each decision just before its Casting line (log time + pull), after the earlier lines of its timestamp
        assert.is_true(R.decisions[3].t > R.pull + 0.1 and R.decisions[3].t < R.pull + 0.1 + 1e-4)
        assert.are.equal("surge", R.next(R.pull + 0.2))
        assert.are.equal("strike", R.next(R.pull + 1.5))
        assert.is_false(R.next(R.pull + 9))
        assert.are.equal(3.8, R.speed) -- the first two main-hand swings
    end)

    it("procs: a mapped proc emits no cast", function()
        local R = replay.new(text(), H, O)
        local W = at(R.world(setmetatable({ tag = "-p" }, { __index = WO }), 1), R.pull + 0.2)
        for _, ev in ipairs(W.truth) do
            assert.is_false(ev.kind == "cast" and ev.spell == 900004)
        end
    end)

    it(
        "power: the truth is each logged after-value, the start the first line's before-value, no regen ticks",
        function()
            local R = replay.new(text(), H, O)
            local W = R.world(setmetatable({ tag = "-w", regen = { [1] = 0.5 } }, { __index = WO }), 1)
            local us = W.ents[1]
            assert.are.equal(50, us.power)
            at(W, R.pull - 1.5)
            assert.are.equal(40, us.power)
            at(W, R.pull + 0.5)
            assert.are.equal(22, us.power)
            at(W, R.pull + 2)
            assert.are.equal(32, us.power)
            assert.are.equal(0.5, W.rates[1]) -- the client reads the content's rate
            for _, ev in ipairs(W.truth) do
                assert.are_not.equal("regen", ev.kind)
            end
        end
    )

    it("auras: forms from the stance auras; a hidden aura in the truth only; a fade's real duration", function()
        local R = replay.new(text(), H, O)
        local W = R.world(setmetatable({ tag = "-a" }, { __index = WO }), 1)
        local us, mob = W.ents[1], W.ents[2]
        at(W, 0.05)
        assert.are.equal(2, us.form) -- the log's opening aura: the second form
        at(W, R.pull - 1.5)
        assert.are.equal(1, us.form)
        at(W, R.pull + 2)
        assert.is_not_nil(us.auras[900020]) -- hidden: in the truth
        for _, ev in ipairs(W.truth) do
            assert.is_false(ev.kind == "aura" and ev.aura == 900020)
        end
        at(W, R.pull + 4.1)
        assert.is_nil(us.auras[900020])
        local mark = mob.auras[900030]
        assert.are.equal(2, mark.stacks)
        local function near(x, y)
            return math.abs(x - y) < 1e-4
        end
        assert.is_true(near(R.pull + 10.1, mark.expires)) -- faded at 10.10: 10 s, not the class's 12
        assert.is_true(near(R.pull - 1 + 120, us.auras[900002].expires)) -- never faded: the class's duration
        assert.is_not_nil(us.avoidAt.DODGE)
    end)

    it("execute: the mob is above 20% before pull + 0.8 x duration and at or under it from then, never dead", function()
        local R = replay.new(text(), H, O)
        local W = R.world(setmetatable({ tag = "-e" }, { __index = WO }), 1)
        local mob = W.ents[2]
        at(W, R.pull + 0.8 * R.duration - 0.01)
        assert.is_true(mob.health > 0.2 * mob.healthMax)
        at(W, R.pull + 0.8 * R.duration)
        assert.is_true(mob.health <= 0.2 * mob.healthMax)
        at(W, R.pull + R.duration)
        assert.is_true(mob.health > 0 and not mob.dead)
        assert.are.equal(R.pull + R.duration, W.stopAt)
    end)
end)
