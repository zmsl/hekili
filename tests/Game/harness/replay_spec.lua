-- tests/Game/harness/replay_spec.lua (wowsims packs plan, Task 3): the wowsims log parser and the log-driven world on
-- the fixture (fixtures/wowsims_test.log, invented IDs), each of the plan's Review Focus lies pinned. The class
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
                lunge = { key = "lunge", id = 900060, gcd = "off", onNextSwing = true },
            },
            auras = {
                shout = { id = 900002, duration = 120 },
                mark = { id = 900030, duration = 12, max_stack = 5 },
                window = { id = 900020, duration = 5 },
                proc = { id = 900040, duration = 15, icd = 10 }, -- a proc aura: gained, then refreshed by a re-proc
                veil = { id = 900050, duration = 3600, isStealthed = true }, -- a stealth aura: IsStealthed's
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
        assert.are.same({ casting = 6, completed = 8, power = 5, aura = 10, stacks = 2, hit = 4 }, kinds)
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

    it("reads the target's Parry, Dodge and Block on us as `taken`, a partial block a BLOCK_REDUCED wound", function()
        local q = replay.parse(table.concat({
            "[4.03] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Parry (SpellSchool: 1). (Threat: 0.000)",
            "[6.34] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Block for 15.9 damage (SpellSchool: 1). (Threat: 15.9)",
            "[7.00] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Block for 0.000 damage (SpellSchool: 1). (Threat: 0.000)",
        }, "\n"))
        assert.are.equal(3, #q.ev)
        assert.are.same({ 4.03, "taken", "PARRY" }, { q.ev[1].t, q.ev[1].kind, q.ev[1].act })
        local e = q.ev[2]
        assert.are.same({ 6.34, "taken", "WOUND", "BLOCK_REDUCED", 15.9 }, { e.t, e.kind, e.act, e.flag, e.amount })
        assert.are.same({ 7, "taken", "BLOCK", 0 }, { q.ev[3].t, q.ev[3].kind, q.ev[3].act, q.ev[3].amount })
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

    it("the pull: the log's earliest line 0.5 s in (at least 5 s), or o.pull; the world runs from it", function()
        assert.are.equal(5, replay.new(text(), H, O).pull) -- its prepull starts at -2
        local early = text():gsub(
            "(\n%[%-2%.00%])",
            "\n[-10.00] [Tester (#1)] Casting {SpellID: 900002} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)\n[-10.00] [Tester (#1)] Completed cast {SpellID: 900002}%1",
            1
        )
        local R = replay.new(early, H, O)
        assert.are.equal(10.5, R.pull)
        assert.are.equal("shout", R.decisions[1].key)
        assert.is_true(math.abs(R.decisions[1].t - 0.5) < 1e-4) -- the prepull cast, a scored decision
        assert.is_true(R.decisions[1].gcd)
        assert.are.equal(12, replay.new(early, H, setmetatable({ pull = 12 }, { __index = O })).pull)
        assert.has_error(function()
            replay.new(early, H, setmetatable({ pull = 5 }, { __index = O }))
        end)
    end)

    it("the mob's creature type: the request's (o.creatureType), else the loop's world knob", function()
        local R = replay.new(text(), H, setmetatable({ creatureType = "undead" }, { __index = O }))
        assert.are.equal("undead", R.world(setmetatable({ tag = "-c" }, { __index = WO }), 1).ents[2].creatureType)
        R = replay.new(text(), H, O)
        local wo = setmetatable({ tag = "-d", creatureType = "demon" }, { __index = WO })
        assert.are.equal("demon", R.world(wo, 1).ents[2].creatureType)
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

    it(
        "a swing and a cast at one instant: the swing and the cast at once, the swing's outcome one landing lag later",
        function()
            local R = replay.new(text(), H, O)
            local W = at(R.world(setmetatable({ tag = "-l" }, { __index = WO }), 1), R.pull + 1)
            local swing, cast, land
            for _, ev in ipairs(W.truth) do
                if ev.kind == "swing" and not swing then
                    swing = ev
                elseif ev.kind == "cast" and ev.spell == 900001 then
                    cast = ev
                elseif ev.kind == "land" then
                    land = ev
                end
            end
            assert.is_true(math.abs(swing.t - (R.pull + 0.1)) < 1e-4 and math.abs(cast.t - swing.t) < 1e-4)
            assert.are.equal(swing, land.swing)
            assert.is_true(math.abs(land.t - swing.t - replay.LAND[1]) < 1e-9) -- after the cast, as the client sees it
            assert.are.equal(42 - 20, W.ents[1].power) -- the truth: the swing's rage paid the strike at 0.10
        end
    )

    it("auras: forms from the stance auras; a hidden aura in the truth only; a natural fade's real duration", function()
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
        assert.is_true(near(R.pull + 10.1, mark.expires)) -- faded at 10.10 with no cast of ours: 10 s, not the class's 12
        assert.is_true(near(R.pull - 1 + 120, us.auras[900002].expires)) -- never faded: the class's duration
        assert.is_not_nil(us.avoidAt.DODGE)
        at(W, R.pull + 10.2)
        assert.is_nil(mob.auras[900030]) -- faded at 10.10: removed then
    end)

    it("ends a cooldown at its cast's log timestamp, not its line's place within it (ready-time ruling)", function()
        local R = replay.new(text(), H, O)
        local W = at(R.world(setmetatable({ tag = "-c" }, { __index = WO }), 1), R.pull + 0.2)
        -- strike's Completed line is the fifth of 0.10: its cooldown still ends at 0.10 + 6, as wowsims's does
        assert.is_true(math.abs(W.ents[1].cdUntil.strike - (R.pull + 0.1 + 6)) < 1e-9)
    end)

    it("keeps an aura whose computed duration grows the aura table while it is read (GAP AT)", function()
        local auras = {}
        for k, a in pairs(H.Hekili.Class.auras) do
            auras[k] = a
        end
        local n = 0
        local grow = { -- the engine's computed field: its read caches entries in the aura table
            __index = function(_, k)
                if k == "duration" then
                    for _ = 1, 4 do -- 3 such entries of 4 each: pairs skipped the stand-in's mark (Lua 5.1's order)
                        n = n + 1
                        auras["cached" .. n] = { id = 920000 + n }
                    end
                    return 1
                end
            end,
        }
        for i = 1, 3 do
            auras["computed" .. i] = setmetatable({ id = 910000 + i }, grow)
        end
        local HG = { Hekili = { Class = { abilities = H.Hekili.Class.abilities, auras = auras } } }
        local R = replay.new(text(), HG, O)
        local W = at(R.world(setmetatable({ tag = "-g" }, { __index = WO }), 1), R.pull + 4.1)
        local mob = W.ents[2]
        assert.is_not_nil(mob.auras[900030]) -- read after the table grew: still kept
    end)

    it("a proc aura's gain and refresh both reach the client: each re-application restarts its expiry", function()
        local R = replay.new(text(), H, O)
        local W = R.world(setmetatable({ tag = "-r" }, { __index = WO }), 1)
        at(W, R.pull + 6)
        local seen = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "aura" and ev.aura == 900040 then
                seen[#seen + 1] = ev.expires - R.pull
            end
        end
        assert.are.equal(2, #seen)
        assert.is_true(math.abs(seen[1] - 17) < 1e-3 and math.abs(seen[2] - 20) < 1e-3)
    end)

    it(
        "an aura a cast removes shows its declared duration, then the removal; a refresh re-reports its expiry",
        function()
            -- the prepull shout (120 s) recast 1.5 s later (wowsims: the cast, faded, gained), refreshed at 2, removed by
            -- a strike at 3; the mark (12 s) fades on its own at 14 (the log's run)
            local R = replay.new(
                table.concat({
                    "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
                    "[-3.00] [Tester (#1)] Aura gained: {SpellID: 900002}",
                    "[-1.50] [Tester (#1)] Casting {SpellID: 900002} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
                    "[-1.50] [Tester (#1)] Completed cast {SpellID: 900002}",
                    "[-1.50] [Tester (#1)] Aura faded: {SpellID: 900002}",
                    "[-1.50] [Tester (#1)] Aura gained: {SpellID: 900002}",
                    "[0.00] [Target 1] Aura gained: {SpellID: 900030}",
                    "[2.00] [Tester (#1)] Aura refreshed: {SpellID: 900002}",
                    "[3.00] [Tester (#1)] Completed cast {SpellID: 900001}",
                    "[3.00] [Tester (#1)] Aura faded: {SpellID: 900002}",
                    "[14.00] [Target 1] Aura faded: {SpellID: 900030}",
                }, "\n"),
                H,
                O
            )
            local W = R.world(setmetatable({ tag = "-e" }, { __index = WO }), 1)
            at(W, R.pull + 15)
            local seen = {}
            for _, ev in ipairs(W.truth) do
                if ev.kind == "aura" then
                    local x = ev.expires > 0 and ev.expires - R.pull or 0
                    seen[#seen + 1] = ("%d %.2f %g"):format(ev.aura, x, ev.duration)
                end
            end
            assert.are.same({
                "900002 117.00 120", -- the prepull application: the declared 120 s, not the 1.5 s it ran
                "900002 0.00 0", -- the recast's removal
                "900002 118.50 120",
                "900030 14.00 14", -- a natural fade: the log's run, not the declared 12 s
                "900002 122.00 120", -- the refresh: its new expiry
                "900002 0.00 0", -- removed at 3
                "900030 0.00 0",
            }, seen)
        end
    )

    it("keeps an aura when another wowsims aura sharing its ID (a tagged one) comes and goes", function()
        local R = replay.new(
            table.concat({
                "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
                "[-1.00] [Tester (#1)] Aura gained: {SpellID: 900002}",
                "[0.50] [Tester (#1)] Aura gained: {SpellID: 900002, Tag: 1}",
                "[0.50] [Tester (#1)] {SpellID: 900002, Tag: 1} stacks: 0 --> 35",
                "[1.00] [Tester (#1)] Aura faded: {SpellID: 900002, Tag: 1}",
                "[1.00] [Target 1] Aura gained: {SpellID: 900030, Tag: -1}", -- a tag alone: still the aura
            }, "\n"),
            H,
            O
        )
        local W = R.world(setmetatable({ tag = "-g" }, { __index = WO }), 1)
        local us, mob = W.ents[1], W.ents[2]
        at(W, R.pull + 2)
        assert.are.same({ 1, true }, { us.auras[900002] and us.auras[900002].stacks, mob.auras[900030] ~= nil })
    end)

    it("a stealth aura flips IsStealthed with UPDATE_STEALTH at its gain and at its removal", function()
        local observer = require("Game.harness.observer")
        local R = replay.new(
            table.concat({
                "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
                "[-1.00] [Tester (#1)] Aura gained: {SpellID: 900050}",
                "[0.00] [Tester (#1)] Completed cast {SpellID: 900001}",
                "[0.00] [Tester (#1)] Aura faded: {SpellID: 900050}",
            }, "\n"),
            H,
            O
        )
        local W = R.world(setmetatable({ tag = "-s" }, { __index = WO }), 1)
        local obs = observer.new(W, observer.DEFAULTS)
        at(W, R.pull + 1)
        obs.step(R.pull + 1)
        local got = {}
        for i = 1, obs.s.n do
            local ev = obs.s.ev[i]
            if ev == "@stealthed" or ev == "UPDATE_STEALTH" then
                got[#got + 1] = ("%s %s %.1f"):format(ev, tostring(obs.s.a1[i]), obs.s.t[i] - R.pull)
            end
        end
        assert.are.same({
            "@stealthed true -1.0",
            "UPDATE_STEALTH nil -1.0",
            "@stealthed false 0.0",
            "UPDATE_STEALTH nil 0.0",
        }, got)
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

    it("replays the target's Parry on us as its swing at us, at the line's time", function()
        local line = "[0.10] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Parry (SpellSchool: 1). (Threat: 0.000)"
        local log = text():gsub("(\n%[0%.10%][^\n]*)", "%1\n" .. line, 1) -- in time order, after the first 0.10 line
        local R = replay.new(log, H, O)
        local W = at(R.world(setmetatable({ tag = "-y" }, { __index = WO }), 1), R.pull + 0.2)
        local got = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" and ev.dst == W.ents[1] then
                got[#got + 1] = { math.floor((ev.t - R.pull) * 1000 + 0.5), ev.act, ev.src == W.ents[2] }
            end
        end
        assert.are.same({ { 100, "PARRY", true } }, got)
    end)

    it("replays an on-next-swing strike's free cast as its queueing press and its paid cast as its landing", function()
        local function line(t, tag, cost)
            local b = "{SpellID: 900060" .. (tag and ", Tag: 1}" or "}")
            local c = "(Cost = " .. cost .. ".000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)"
            return ("\n[%s] [Tester (#1)] Casting %s %s"):format(t, b, c)
                .. ("\n[%s] [Tester (#1)] Completed cast %s"):format(t, b)
        end
        local queued = "\n[2.05] [Tester (#1)] Aura gained: {SpellID: 900060, Tag: 1}" -- its queue aura
        -- Heroic Strike's tags (Tag 1 the free queueing cast) and Maul's (the paid landing tagged)
        for _, tags in ipairs({ { true, false }, { false, true } }) do
            local log = text():gsub("(\n%[2%.00%][^\n]*)", "%1" .. line("2.00", tags[1], 0) .. queued, 1)
            log = log:gsub("(\n%[3%.90%][^\n]*Dodge)", "%1" .. line("3.90", tags[2], 9), 1)
            local R = replay.new(log, H, O)
            local W = at(R.world(setmetatable({ tag = "-q" }, { __index = WO }), 1), R.pull + 4)
            local got = {}
            for _, ev in ipairs(W.truth) do
                if ev.spell == 900060 then
                    got[#got + 1] = { ev.kind, math.floor((ev.t - R.pull) * 100 + 0.5) }
                end
            end
            assert.are.same({ { "queue", 200 }, { "unqueue", 390 }, { "cast", 390 } }, got)
            assert.are.equal("strike", R.next(R.pull + 2.5)) -- the landing is no press: the next is 8.10's strike
        end
    end)

    it("fails an on-next-swing strike's free cast that queues no aura before its next cast (a free landing)", function()
        local function line(t, cost)
            local b, c =
                "{SpellID: 900060}", "(Cost = " .. cost .. ".000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)"
            return ("\n[%s] [Tester (#1)] Casting %s %s"):format(t, b, c)
                .. ("\n[%s] [Tester (#1)] Completed cast %s"):format(t, b)
        end
        local log = text():gsub("(\n%[2%.00%][^\n]*)", "%1" .. line("2.00", 0), 1)
        log = log:gsub("(\n%[3%.90%][^\n]*Dodge)", "%1" .. line("3.90", 9), 1)
        assert.has_error(function()
            replay.new(log, H, O)
        end, "the free lunge at 2 queues no aura")
    end)

    it("replays a partial block on us as the client's BLOCK_REDUCED wound, our health untouched", function()
        local line =
            "[0.10] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Block for 40 damage (SpellSchool: 1). (Threat: 40)"
        local R = replay.new(text():gsub("(\n%[0%.10%][^\n]*)", "%1\n" .. line, 1), H, O)
        local W = R.world(setmetatable({ tag = "-b" }, { __index = WO }), 1)
        local h = W.ents[1].health
        at(W, R.pull + 0.2)
        local got = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" and ev.dst == W.ents[1] then
                got[#got + 1] = { ev.act, ev.flag, ev.amount }
            end
        end
        assert.are.same({ { "WOUND", "BLOCK_REDUCED", 40 } }, got)
        assert.are.equal(h, W.ents[1].health)
    end)
end)

describe("the replay's casts: tags, items, pets, totems", function()
    local LOG = table.concat({
        "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
        "[-1.00] [Tester (#1)] Casting {SpellID: 900005} (Cost = 0.000, Cast Time = 0s, GCD = 1s, Effective Time = 1s)",
        "[-1.00] [Tester (#1)] Completed cast {SpellID: 900005}",
        "[0.50] [Tester (#1)] Casting {SpellID: 900005, Tag: 1} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)",
        "[0.50] [Tester (#1)] Completed cast {SpellID: 900005, Tag: 1}",
        "[1.00] [Tester (#1)] Casting {ItemID: 800001} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)",
        "[1.00] [Tester (#1)] Completed cast {ItemID: 800001}",
        "[2.00] [Tester (#1) - Wolf] Casting {SpellID: 900001} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[2.00] [Tester (#1) - Wolf] Completed cast {SpellID: 900001}",
    }, "\n")
    local HT = {
        Hekili = {
            Class = {
                abilities = {
                    strike = { key = "strike", id = 900001, gcd = "spell" },
                    fire_post = { key = "fire_post", id = 900005, gcd = "totem" },
                    rune = { key = "rune", id = -101, items = { 800002, 800001 }, cooldown = 120, gcd = "off" },
                },
                auras = {},
            },
        },
    }
    local OT = { procs = { ["900005:1"] = true }, totems = { fire_post = { 1, 300 } } }

    it("drops only the proc's tag, maps an item cast, skips a pet's, summons a totem", function()
        local R = replay.new(LOG, HT, OT)
        local keys = {}
        for i, d in ipairs(R.decisions) do
            keys[i] = d.key
        end
        assert.are.same({ "fire_post", "rune" }, keys)
        local W = at(R.world(setmetatable({ tag = "-t" }, { __index = WO }), 1), R.pull + 1.5)
        local us = W.ents[1]
        local tt = W.totem(us, 1)
        assert.are.equal(900005, tt and tt.spell)
        assert.is_true(math.abs(us.cdUntil.rune - (R.pull + 1 + 120)) < 1e-3)
        local casts = 0
        for _, ev in ipairs(W.truth) do
            casts = casts + (ev.kind == "cast" and 1 or 0)
        end
        assert.are.equal(1, casts) -- the totem's; the proc, the item and the pet emit none
    end)
end)

-- Fix 31 G4: an item use the kit does not map is still our cast to the client (its UNIT_SPELLCAST_SUCCEEDED, of a
-- spell no ability has), so its outcome a travel later is not our pending cast's to claim (Rows.lua's another()).
describe("the replay's unmapped item use", function()
    local LOG = table.concat({
        "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
        "[0.00] [Tester (#1)] Casting {ItemID: 800009} (Cost = 0.000, Cast Time = 1s, GCD = 0s, Effective Time = 1s)",
        "[1.00] [Tester (#1)] Completed cast {ItemID: 800009}",
        "[1.00] [Tester (#1)] Casting {SpellID: 900001} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[1.00] [Tester (#1)] Completed cast {SpellID: 900001}",
        "[2.43] [Tester (#1)] [Target 1] {ItemID: 800009} Miss (SpellSchool: 4). (Threat: 0.000)",
    }, "\n")

    it("emits its success as a cast of no ability's spell, then ours, then its outcome", function()
        local R = replay.new(LOG, H, O)
        local W = at(R.world(WO, 1), R.pull + 3)
        local got = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" or ev.kind == "castStart" or ev.kind == "spell" then
                got[#got + 1] = ev.kind .. ":" .. tostring(ev.spell or ev.act)
            end
        end
        assert.are.same({ "cast:" .. replay.UNMAPPED_SPELL, "cast:900001", "spell:MISS" }, got)
        assert.is_nil(H.Hekili.Class.abilities[replay.UNMAPPED_SPELL])
    end)
end)

-- Fix 31 G5: our pet's power lines ("<Name> (#1) - <Pet>") are its pool's truth, as the log's after-values are ours:
-- the world's pet follows them (no modelled regen), the client's UnitPower("pet") answers them, and they are never ours.
describe("the replay's pet power", function()
    local observer = require("Game.harness.observer")
    local LOG = table.concat({
        "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
        "[1.00] [Tester (#1) - Imp] Spent 115.000 mana from {SpellID: 900070} (2000.000 --> 1885.000) of 2000 total.",
        "[1.10] [Tester (#1) - Imp] Gained 1.700 mana from {OtherID: 2, Tag: 2} (1885.000 --> 1886.700) of 2000 total.",
        "[2.00] [Tester (#1) - Imp] Spent 115.000 mana from {SpellID: 900070} (1886.700 --> 1771.700) of 2000 total.",
    }, "\n")

    it("moves the world's pet to each logged after-value and answers it to the client", function()
        local p = replay.parse(LOG)
        assert.is_nil(replay.manaRegen(p.ev)) -- the pet's regen lines are not our mana's
        local R = replay.new(LOG, H, O)
        local wo = setmetatable({ pet = { pt = 0, max = 2000, regen = 50, tick = 2 } }, { __index = WO })
        local W = R.world(wo, 1)
        local us = W.ents[1]
        local obs = observer.new(W, setmetatable({}, { __index = observer.DEFAULTS }))
        W.run(R.pull + 1.5)
        assert.is_true(math.abs(us.pet.power - 1886.7) < 1e-9)
        W.run(R.pull + 5)
        obs.step(R.pull + 5)
        assert.is_true(math.abs(us.pet.power - 1771.7) < 1e-9) -- no modelled regen on top
        local got = {}
        for i = 1, obs.s.n do
            if obs.s.ev[i] == "@petPower" then
                got[#got + 1] = obs.s.a1[i]
            end
        end
        assert.are.same({ 1885, 1886.7, 1771.7 }, got)
        assert.are.equal(0, us.power0) -- our own pool untouched
    end)
end)

describe("the replay's channels and hard casts (central fix 22, gap BC)", function()
    local LOG = table.concat({
        "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
        "[0.00] [Tester (#1)] Casting {SpellID: 900060} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[0.00] [Tester (#1)] Completed cast {SpellID: 900060}",
        "[0.00] [Target 1] Aura gained: {SpellID: 900060}",
        "[1.00] [Tester (#1)] [Target 1] {SpellID: 900060} tick Hit for 50.000 damage (SpellSchool: 64). (Threat: 50.000)",
        "[2.00] [Tester (#1)] [Target 1] {SpellID: 900060} tick Hit for 50.000 damage (SpellSchool: 64). (Threat: 50.000)",
        "[2.50] [Target 1] Aura faded: {SpellID: 900060}",
        "[2.50] [Tester (#1)] Casting {SpellID: 900061} (Cost = 0.000, Cast Time = 2s, GCD = 1.5s, Effective Time = 2s)",
        "[4.50] [Tester (#1)] Completed cast {SpellID: 900061}",
        "[5.00] [Tester (#1)] Casting {SpellID: 900062} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[5.00] [Tester (#1)] Completed cast {SpellID: 900062}",
    }, "\n")
    local HC = {
        Hekili = {
            Class = {
                abilities = {
                    beam = { key = "beam", id = 900060, cast = 5, channeled = true, gcd = "spell" },
                    bolt = { key = "bolt", id = 900061, cast = 2, gcd = "spell" },
                    drain = { key = "drain", id = 900062, cast = 3, channeled = true, gcd = "spell" },
                },
                auras = {},
            },
        },
    }

    it("feeds a channel's start and its stop at the aura's fade (else its declared length), a cast's START", function()
        local R = replay.new(LOG, HC)
        local W = at(R.world(WO, 1), R.pull + 10)
        local s = require("Game.harness.observer").observe(W, require("Game.harness.observer").DEFAULTS)
        local function rel(ms)
            return ms and ("%.2f"):format(ms / 1000 - R.pull) or "nil"
        end
        local out = {}
        for i = 1, s.n do
            local ev = s.ev[i]
            local head = ("%.2f %s"):format(s.t[i] - R.pull, ev)
            if ev == "@casting" or ev == "@channel" then
                out[#out + 1] = head .. " " .. rel(s.a1[i]) .. " " .. rel(s.a2[i])
            elseif ev:match("^UNIT_SPELLCAST") and ev ~= "UNIT_SPELLCAST_SENT" and s.a1[i] == "player" then
                out[#out + 1] = head .. " " .. tostring(s.a3[i])
            end
        end
        assert.are.same({
            "0.00 @channel 0.00 2.50",
            "0.00 UNIT_SPELLCAST_CHANNEL_START 900060",
            "0.00 UNIT_SPELLCAST_SUCCEEDED 900060",
            "2.50 @channel nil nil",
            "2.50 UNIT_SPELLCAST_CHANNEL_STOP 900060",
            "2.50 @casting 2.50 4.50",
            "2.50 UNIT_SPELLCAST_START 900061",
            "4.50 @casting nil nil",
            "4.50 UNIT_SPELLCAST_SUCCEEDED 900061",
            "4.50 UNIT_SPELLCAST_STOP 900061",
            "5.00 @channel 5.00 8.00",
            "5.00 UNIT_SPELLCAST_CHANNEL_START 900062",
            "5.00 UNIT_SPELLCAST_SUCCEEDED 900062",
            "8.00 @channel nil nil",
            "8.00 UNIT_SPELLCAST_CHANNEL_STOP 900062",
        }, out)
    end)
end)

describe("the replay's cooldowns: the engine's, a shared category's, the log's", function()
    local LOG = table.concat({
        "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 20 s target 63",
        "[0.00] [Tester (#1)] Casting {SpellID: 900051} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[0.00] [Tester (#1)] Completed cast {SpellID: 900051}",
        "[1.50] [Tester (#1)] Casting {SpellID: 900060} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[1.50] [Tester (#1)] Completed cast {SpellID: 900060}",
        "[9.50] [Tester (#1)] Casting {SpellID: 900060} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[9.50] [Tester (#1)] Completed cast {SpellID: 900060}",
        "[12.00] [Tester (#1)] Casting {SpellID: 900052} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[12.00] [Tester (#1)] Completed cast {SpellID: 900052}",
        "[15.00] [Tester (#1)] Casting {SpellID: 900052} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[15.00] [Tester (#1)] Completed cast {SpellID: 900052}",
    }, "\n")
    local function talented() -- a talent-shortened cooldown: the kit's function, the engine's answer
        return 6
    end
    local HC = {
        Hekili = {
            Class = {
                abilities = {
                    shock_a = { key = "shock_a", id = 900050, copy = { 900051 }, cooldown = talented, gcd = "spell" },
                    shock_b = { key = "shock_b", id = 900052, cooldown = talented, gcd = "spell" },
                    quake = { key = "quake", id = 900060, cooldown = talented, gcd = "spell" },
                },
                auras = {},
            },
            State = {
                action = setmetatable({}, {
                    __index = function(_, k)
                        assert(k ~= "quake", "the engine cannot say") -- quake falls back to the log's spacing
                        return { cooldown = 5 } -- Reverberation-like: 6 s less a talent's 1 s
                    end,
                }),
            },
        },
    }

    it("passes the engine's talent-modified cooldown, a category's on every member, the log's spacing else", function()
        local R = replay.new(LOG, HC, { shared = { shock_a = "shock_b", shock_b = { "shock_a" } } })
        local W = at(R.world(setmetatable({ tag = "-cd" }, { __index = WO }), 1), R.pull + 10)
        local us, casts = W.ents[1], {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" then
                casts[#casts + 1] = ev
            end
        end
        assert.are.equal(3, #casts)
        assert.are.same({ 900051, { 900050, 900051, 900052 } }, { casts[1].spell, casts[1].ids })
        -- less its line's place in its timestamp, n x replay.EPS by construction (the ready-time ruling), not float order:
        -- the cast's cooldown runs from the timestamp's start, so do not "fix" the subtraction
        assert.is_true(math.abs(casts[1].cd - 5) < 1e-5)
        assert.is_true(math.abs(us.cdUntil.shock_a - (R.pull + 5)) < 1e-3)
        assert.is_true(math.abs(us.cdUntil.shock_b - (R.pull + 5)) < 1e-3) -- the category: both together
        assert.are.same({ 8, { 900060 } }, { tonumber(("%.4f"):format(casts[2].cd)), casts[2].ids })
        -- the engine's 5 s capped at the log's 3 s spacing: wowsims did cast it that soon
        at(W, R.pull + 13)
        local last
        for _, ev in ipairs(W.truth) do
            last = ev.kind == "cast" and ev or last
        end
        assert.are.same({ 900052, 3 }, { last.spell, tonumber(("%.4f"):format(last.cd)) })
        local plain = replay.new(LOG, HC) -- no category: only the cast's own ranks
        W = at(plain.world(setmetatable({ tag = "-cd2" }, { __index = WO }), 1), plain.pull + 1)
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" then
                assert.are.same({ 900050, 900051 }, ev.ids)
            end
        end
        assert.is_nil(W.ents[1].cdUntil.shock_b)
    end)
end)

describe("the replay's position", function()
    local f = assert(io.open("tests/Game/harness/fixtures/wowsims_move.log", "rb"))
    local log = f:read("*a")
    f:close()

    it("reads the Movement aura's stacks as our yards to the target, its fade as no news", function()
        local moves = {}
        for _, e in ipairs(replay.parse(log).ev) do
            if e.kind == "move" then
                moves[#moves + 1] = e.distance
            end
            assert.is_not_equal("stacks", e.kind) -- an OtherID aura's stacks are no spell's
        end
        assert.are.same({ 11, 10, 9, 8, 7, 6, 5 }, moves)
    end)

    it("starts at the request's distance and steps it on the log's moves", function()
        local R = replay.new(log, H, { distance = 25 })
        local W = R.world(WO, 1)
        assert.are.equal(25, at(W, 0.05).distance)
        assert.are.equal(11, at(W, replay.PULL + 0.515).distance)
        assert.are.equal(5, at(W, replay.PULL + 2).distance)
        local n = 0
        for _, ev in ipairs(W.truth) do
            n = n + (ev.kind == "move" and 1 or 0)
        end
        assert.are.equal(8, n)
        assert.is_nil(replay.new(log, H).world(WO, 1).distance) -- no request distance: no positions until a move
    end)
end)

describe("the replay's mana regen (wowsims's regen lines)", function()
    local observer = require("Game.harness.observer")
    local fake = require("Game.State.helpers.fake_api")
    local function line(t, amount, tag)
        return ("[%.2f] [Tester (#1)] Gained %.3f mana from {OtherID: 2, Tag: %d} (100.000 --> 102.200) of 4000 total."):format(
            t,
            amount,
            tag
        )
    end
    local function log(rows)
        local out = { "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63" }
        for _, r in ipairs(rows) do
            out[#out + 1] = line(r[1], r[2], r[3])
        end
        return table.concat(out, "\n")
    end

    it("reads each tag's usual tick a second; a casting rate above the idle one is a boost (casting 0)", function()
        -- not casting 2.2 a tick (one partial 0.132, one boosted 3.1), casting only under a boost (11 a tick)
        local p = replay.parse(
            log({ { 1, 11, 1 }, { 1.1, 11, 1 }, { 3, 0.132, 2 }, { 3.1, 2.2, 2 }, { 3.2, 2.2, 2 }, { 3.3, 3.1, 2 } })
        )
        local idle, casting = replay.manaRegen(p.ev)
        assert.is_true(math.abs(idle - 22) < 1e-9)
        assert.are.equal(0, casting)
        idle, casting = replay.manaRegen(replay.parse(log({ { 1, 0.3, 1 }, { 1.1, 0.3, 1 }, { 7, 2.5, 2 } })).ev)
        assert.is_true(math.abs(idle - 25) < 1e-9 and math.abs(casting - 3) < 1e-9) -- mp5 while casting
        assert.is_nil(replay.manaRegen(replay.parse(log({})).ev))
    end)

    it("answers them to the client out of combat (W.fsr, the fake's GetManaRegen), secret in combat", function()
        local R = replay.new(log({ { 0.5, 2.2, 2 }, { 0.6, 2.2, 2 } }), H, {})
        local W = R.world(setmetatable({ tag = "-m" }, { __index = WO }), 1)
        local us = W.ents[1]
        assert.are.same({ 22, 0 }, { W.regenRate(us, 0, "idle"), W.regenRate(us, 0, "casting") })
        local obs = observer.new(W, setmetatable({}, { __index = observer.DEFAULTS }))
        W.run(R.pull + 0.1)
        obs.step(R.pull + 0.1)
        local api = fake.new()
        local s, seen = obs.s, 0
        for i = 1, s.n do
            if s.ev[i] == "@regen" and s.a1[i] == 0 then
                api.ctl.regen[0] = s.a2[i] and { s.a2[i], s.a3[i] } or nil -- as drive.lua applies it
                seen = seen + 1
                if seen == 1 then
                    assert.are.same({ 22, 0 }, { api.GetManaRegen() }) -- the prepull read: plain
                end
            end
        end
        assert.are.equal(2, seen)
        assert.are.equal(fake.SECRET, (api.GetManaRegen())) -- the pull: secret, the facade's model answers
    end)

    it("gives the world each logged pool at the log's maximum, and the client its UnitPowerMax", function()
        local R = replay.new(log({ { 0.5, 2.2, 2 } }), H, {}) -- a mana line "of 4000 total"; the world's power: rage
        local W = R.world(setmetatable({ tag = "-x" }, { __index = WO }), 1)
        local us = W.ents[1]
        assert.are.same({ 100, 4000 }, { us.res[0].cur, us.res[0].max }) -- its first line's before-value, its pool
        local obs = observer.new(W, setmetatable({ powerMax = true }, { __index = observer.DEFAULTS }))
        W.run(R.pull - 0.2)
        obs.step(R.pull - 0.2)
        local got = {}
        for i = 1, obs.s.n do
            if obs.s.ev[i] == "@powerMax" then
                got[obs.s.a1[i]] = obs.s.a2[i]
            end
        end
        assert.are.same({ [1] = 100, [0] = 4000 }, got)
    end)
end)

describe("the replay's avoided casts", function()
    -- wowsims's order for an avoided ability: the cast, its spend, the 80% refund (OtherID 8), then the outcome
    local LOG = table.concat({
        "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
        "[1.00] [Tester (#1)] Casting {SpellID: 900001} (Cost = 15.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[1.00] [Tester (#1)] Completed cast {SpellID: 900001}",
        "[1.00] [Tester (#1)] Spent 15.000 rage from {SpellID: 900001} (50.000 --> 35.000) of 100 total.",
        "[1.00] [Tester (#1)] Gained 12.000 rage from {OtherID: 8} (35.000 --> 47.000) of 100 total.",
        "[1.00] [Tester (#1)] [Target 1] {SpellID: 900001} Dodge (SpellSchool: 1). (Threat: 0.000)",
    }, "\n")

    it("emits the cast, its powers, then the target's DODGE of it (no wound), in the log's order", function()
        local R = replay.new(LOG, H, O)
        local W = at(R.world(WO, 1), R.pull + 2)
        local kinds = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" or ev.kind == "gain" or ev.kind == "spell" then
                kinds[#kinds + 1] = ev.kind .. ":" .. tostring(ev.act or ev.rage or ev.cost)
            end
        end
        assert.are.same({ "cast:nil", "gain:15", "gain:12", "spell:DODGE" }, kinds)
        assert.are.equal(47, W.ents[1].power)
    end)

    it("a white swing's Miss 0.06 s after a cast stays the swing's (the Rogue log's opening Garrote)", function()
        local log = table.concat({
            "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63",
            "[1.00] [Tester (#1)] Casting {SpellID: 900001} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
            "[1.00] [Tester (#1)] Completed cast {SpellID: 900001}",
            "[1.06] [Tester (#1)] Completed cast {OtherID: 3, Tag: 1}",
            "[1.06] [Tester (#1)] [Target 1] {OtherID: 3, Tag: 1} Miss (SpellSchool: 1). (Threat: 0.000)",
        }, "\n")
        local R = replay.new(log, H, O)
        local W = at(R.world(WO, 1), R.pull + 2)
        local kinds = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" or ev.kind == "swing" or ev.kind == "land" or ev.kind == "spell" then
                kinds[#kinds + 1] = ev.kind .. ":" .. tostring(ev.act)
            end
        end
        assert.are.same({ "cast:nil", "swing:MISS", "land:MISS" }, kinds)
    end)
end)
