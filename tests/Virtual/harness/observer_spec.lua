-- tests/Virtual/harness/observer_spec.lua (harness design §3.1 layer 4): each observer rule on a one-event true stream.
local world = require("Virtual.harness.world")
local entities = require("Virtual.harness.entities")
local observer = require("Virtual.harness.observer")
local behaviours = require("Virtual.harness.behaviours")
local scenarios = require("Virtual.harness.scenarios")
local fake = require("Virtual.State.helpers.fake_api")

describe("the observer", function()
    local W, us, mob

    -- A world with us (two weapons) attacking a mob that attacks us, and `n` party members.
    local function setup(n)
        W = world.new(7)
        us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } } }))
        us.target, mob.target = mob, us
        for i = 1, n or 0 do
            W.add(entities.new({ guid = "Other-" .. i })).target = mob
        end
    end

    -- The stream's events from `from` on, as { t, ev, a1, a2, a3, a4, a5, src } (ops included).
    local function events(s, from)
        local out = {}
        for i = 1, s.n do
            if s.t[i] >= (from or 0) and not (s.ev[i] == "@usable" and s.t[i] == 0) then
                out[#out + 1] = { s.t[i], s.ev[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i], s.src[i] }
            end
        end
        return out
    end

    it("fires our swing, then its outcome on the target's plate and the target in the same ms", function()
        setup()
        local sw = W.emit({
            t = 5,
            kind = "swing",
            src = us,
            dst = mob,
            hand = 2,
            act = "WOUND",
            flag = "",
            amount = 30,
            speed = 2.5,
        })
        W.emit({
            t = 5.7,
            kind = "land",
            src = us,
            dst = mob,
            hand = 2,
            act = "WOUND",
            flag = "",
            amount = 30,
            school = 1,
            swing = sw,
        })
        local s = observer.observe(W)
        assert.are.same({
            { 5, "PLAYER_SWING", 2.5, 1, nil, nil, nil, 0 },
            { 5.7, "UNIT_COMBAT", "nameplate1", "WOUND", "", 30, 1, 1 },
            { 5.7, "UNIT_COMBAT", "target", "WOUND", "", 30, 1, 1 },
        }, events(s))
        local i = s.n -- the target's row, last
        assert.are.same({ "target", 2, 5 }, { s.a1[i], s.hand[i], s.swingT[i] })
    end)

    it("fires a hit on us for player, then targettarget while our target targets us; another's on partyN", function()
        setup(1)
        local other = W.ents[3]
        W.emit({
            t = 3,
            kind = "swing",
            src = mob,
            dst = us,
            hand = 1,
            act = "PARRY",
            flag = "",
            amount = 0,
            school = 1,
        })
        mob.target = other
        W.emit({
            t = 4,
            kind = "swing",
            src = mob,
            dst = us,
            hand = 1,
            act = "WOUND",
            flag = "",
            amount = 12,
            school = 1,
        })
        W.emit({
            t = 5,
            kind = "swing",
            src = mob,
            dst = other,
            hand = 1,
            act = "WOUND",
            flag = "",
            amount = 13,
            school = 1,
        })
        local got = events(observer.observe(W))
        assert.are.same({
            { 3, "UNIT_COMBAT", "player", "PARRY", "", 0, 1, 2 },
            { 3, "UNIT_COMBAT", "targettarget", "PARRY", "", 0, 1, 2 },
            { 4, "UNIT_COMBAT", "player", "WOUND", "", 12, 1, 2 },
            { 5, "UNIT_COMBAT", "party1", "WOUND", "", 13, 1, 2 },
        }, got)
    end)

    it("fires another source's outcome on our target's tokens; its casts with secret IDs, ours plain", function()
        setup(1)
        local other = W.ents[3]
        W.emit({ t = 2, kind = "cast", src = other, dst = mob, spell = "SECRET" })
        W.emit({ t = 2, kind = "spell", src = other, dst = mob, act = "WOUND", flag = "", amount = 37, school = 8 })
        W.emit({ t = 3, kind = "cast", src = us, dst = mob, spell = "DOT", cost = 10 })
        local got = events(observer.observe(W))
        assert.are.same({ 2, "UNIT_SPELLCAST_SUCCEEDED", "party1", fake.SECRET, fake.SECRET }, { unpack(got[1], 1, 5) })
        assert.are.same({ "nameplate1", 37, 8, 2 }, { got[2][3], got[2][6], got[2][7], got[2][8] })
        assert.are.same({ "target", 37, 8, 2 }, { got[3][3], got[3][6], got[3][7], got[3][8] })
        assert.are.same({ 3, "UNIT_SPELLCAST_SUCCEEDED", "player" }, { got[4][1], got[4][2], got[4][3] })
        assert.is_number(got[4][5])
    end)

    it(
        "fires a queued strike's frame: our swing, a WOUND 0 and our success in its rolled order, then no longer current, its wound 1 ms later",
        function()
            local orders = {}
            for order = 1, 2 do
                setup()
                W.emit({
                    t = 6,
                    kind = "strike",
                    src = us,
                    dst = mob,
                    hand = 1,
                    act = "WOUND",
                    flag = "",
                    amount = 80,
                    school = 1,
                    spell = "STRIKE",
                    speed = 2.2,
                    order = order, -- the behaviour's roll
                })
                local got = events(observer.observe(W))
                local o = {}
                for _, e in ipairs(got) do
                    o[#o + 1] = e[2] == "UNIT_COMBAT" and (e[3] .. e[6]) or e[2]
                end
                orders[order] = table.concat(o, " ")
                assert.are.same({ 6.001, "target", 80, 1 }, { got[#got][1], got[#got][3], got[#got][6], got[#got][8] })
            end
            assert.are.same({
                "UNIT_SPELLCAST_SUCCEEDED nameplate10 target0 PLAYER_SWING @current nameplate180 target80",
                "PLAYER_SWING nameplate10 target0 UNIT_SPELLCAST_SUCCEEDED @current nameplate180 target80",
            }, orders)
        end
    )

    it("fires another player's strike frame as a WOUND 0 and its damage 1 ms later, with no cast", function()
        setup(1)
        W.emit({
            t = 6,
            kind = "strike",
            src = W.ents[3],
            dst = mob,
            hand = 1,
            act = "WOUND",
            flag = "",
            amount = 36,
            school = 1,
        })
        local got = events(observer.observe(W))
        assert.are.same({ 6, 6, 6.001, 6.001 }, { got[1][1], got[2][1], got[3][1], got[4][1] })
        assert.are.same({ 0, 0, 36, 36 }, { got[1][6], got[2][6], got[3][6], got[4][6] })
        assert.are.equal(4, #got)
    end)

    it("fires the on-swing proc as a school-32 wound on the target and a heal on us, same ms", function()
        setup()
        W.emit({ t = 7.002, kind = "proc", src = us, dst = mob, act = "WOUND", amount = 36, school = 32 })
        local got = events(observer.observe(W))
        assert.are.same({ "nameplate1", "WOUND", 36, 32 }, { got[1][3], got[1][4], got[1][6], got[1][7] })
        assert.are.same({ "target", "WOUND", 36, 32 }, { got[2][3], got[2][4], got[2][6], got[2][7] })
        assert.are.same({ "player", "HEAL", 36, 1 }, { got[3][3], got[3][4], got[3][6], got[3][7] })
        assert.are.same({ "targettarget", "HEAL" }, { got[4][3], got[4][4] })
        assert.are.equal(7.002, got[4][1])
    end)

    it("fires the avoid our swing rolled in its ms (at its share), and lands our hands at their lags", function()
        setup()
        mob.health = 1e9
        behaviours.melee({ land = observer.lag(), sameMs = observer.DEFAULTS.sameMs })(W, us)
        W.run(3600)
        local rolled, swings, sameMs = 0, 0, 0
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" then
                swings, rolled = swings + 1, rolled + (ev.sameMs and 1 or 0)
            end
        end
        local s = observer.observe(W)
        for i = 1, s.n do
            sameMs = sameMs + (s.src[i] == 3 and s.a1[i] == "target" and 1 or 0)
        end
        assert.are.equal(rolled, sameMs)
        assert.is_true(math.abs(sameMs / swings - 3 / 87) < 0.01, "same-ms share " .. sameMs / swings)
        local lag, main, own, mref = observer.lag(), {}, 0, 0
        local n = 1500
        for k = 1, n do -- a main swing, then an off swing 0.3 s later
            local t = 4000 + k * 2.5
            local d = lag(W, us, 1, t)
            us.lastSwing[1], us.landAt[1], main[#main + 1] = t, t + d, d
            d = lag(W, us, 2, t + 0.3)
            if math.abs(d - 0.703) < 0.03 then
                own = own + 1
            elseif math.abs(0.3 + d - 1.686) < 0.03 then
                mref = mref + 1
            end
        end
        table.sort(main)
        assert.is_true(math.abs(main[n / 2] - 0.474) < 0.01, "main median " .. main[n / 2])
        assert.is_true(math.abs(own / n - observer.DEFAULTS.off.pOwn) < 0.05, "off own share")
        assert.is_true(math.abs(mref / n - observer.DEFAULTS.off.pMain) < 0.05, "off main-reference share")
    end)

    it("answers usability from our true power: a gain flips it a knob's delay later, our spend at once", function()
        setup()
        local land = { t = 4, kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", flag = "", amount = 40 }
        land.school, land.swing, land.rage = 1, { t = 3.5 }, 12
        W.emit(land)
        W.emit({ t = 5, kind = "cast", src = us, dst = mob, spell = "CAST", cost = 10 })
        local got = events(observer.observe(W, setmetatable({ usable = true }, { __index = observer.DEFAULTS })), 1)
        local cast, dot = observer.COSTS[1][1], observer.COSTS[3][1]
        assert.are.same({
            { 4, "UNIT_COMBAT", "nameplate1", "WOUND", "", 40, 1, 1 },
            { 4, "UNIT_COMBAT", "target", "WOUND", "", 40, 1, 1 },
            { 4, "@truth", 12, nil, nil, nil, nil, 0 },
            { 4.1, "@usable", cast, 1, nil, nil, nil, 0 },
            { 4.1, "@usable", dot, 1, nil, nil, nil, 0 },
            { 4.1, "SPELL_UPDATE_USABLE", nil, nil, nil, nil, nil, 0 },
            { 5, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", observer.SPELLS.CAST, nil, nil, 0 },
            { 5, "UNIT_SPELLCAST_SUCCEEDED", "targettarget", "Cast-1", observer.SPELLS.CAST, nil, nil, 0 },
            { 5, "@truth", 2, nil, nil, nil, nil, 0 },
            { 5, "@usable", cast, 2, nil, nil, nil, 0 },
            { 5, "@usable", dot, 2, nil, nil, nil, 0 },
            { 5, "SPELL_UPDATE_USABLE", nil, nil, nil, nil, nil, 0 },
        }, got)
    end)

    it(
        "reads the weapon damage cache out of combat only: before the pull and at the stop, not at a form change",
        function()
            setup()
            W.emit({ t = 1.5, kind = "prepull" })
            W.emit({ t = 2, kind = "pull" })
            us.dmgMult = 1.2 -- a damage buff in combat: no read until the stop
            W.emit({ t = 3, kind = "form", form = 1 })
            W.emit({ t = 9, kind = "stop" })
            local damage, form = {}, nil
            local s = observer.observe(W)
            for i = 1, s.n do
                if s.ev[i] == "@damage" then
                    damage[#damage + 1] = { s.t[i], s.a2[i] }
                elseif s.ev[i] == "UPDATE_SHAPESHIFT_FORM" then
                    form = s.t[i]
                end
            end
            assert.are.same({ { 1.5, 50 }, { 9, 60 } }, damage)
            assert.are.equal(3, form)
        end
    )

    it("makes the target's auras raise in combat, and answers UnitIsUnit secret under its knob", function()
        setup()
        W.emit({ t = 1.5, kind = "prepull" })
        W.emit({ t = 2, kind = "pull" })
        W.emit({ t = 9, kind = "stop" })
        local k = setmetatable({ secretUnitIs = true }, { __index = observer.DEFAULTS })
        local s = observer.observe(W, k)
        local aura, unitIs = {}, nil
        for i = 1, s.n do
            if s.ev[i] == "@auraError" then
                aura[#aura + 1] = { s.t[i], s.a1[i], s.a2[i] }
            elseif s.ev[i] == "@unitIs" and s.a1[i] == "nameplate1target" then
                unitIs = s.a2[i]
            end
        end
        assert.are.same({ { 2, "target", true }, { 9, "target", false } }, aura)
        assert.is_true(rawequal(fake.SECRET, unitIs))
    end)

    it("steps to the batch's stream in 0.2 s steps, and draws nothing from the world's generator", function()
        local o = scenarios.oracle({ duration = 40, others = { "melee", "caster" } })
        local k = setmetatable({ usable = true }, { __index = observer.DEFAULTS })
        local batch = observer.observe(scenarios.build(o, 3), k)
        local W2 = scenarios.build(o, 3)
        local obs = observer.new(W2, k)
        local steps = 0
        for t = 0, 50, 0.2 do
            local first, last = obs.step(t)
            assert.is_true(last >= first - 1)
            steps = steps + 1
        end
        obs.step(math.huge)
        for _, f in ipairs({ "t", "ev", "a1", "a2", "a3", "a4", "a5", "src", "hand", "swingT", "actor" }) do
            for i = 1, batch.n do
                assert.is_true(rawequal(batch[f][i], obs.s[f][i]), f .. " " .. i)
            end
        end
        assert.are.equal(batch.n, obs.s.n)
        local W3 = scenarios.build(o, 3) -- the same world, never observed
        assert.are.equal(W3.rng.next(), W2.rng.next())
    end)

    it(
        "answers the content's usability: a power answer a delay after the gain, a world answer at the step's end",
        function()
            setup()
            mob.health = 1000
            local k = setmetatable({
                usable = {
                    {
                        101,
                        function(_, _, p)
                            return p >= 10
                        end,
                    },
                    {
                        102,
                        function(_, e)
                            return e.target.health < 200
                        end,
                    },
                },
            }, { __index = observer.DEFAULTS })
            local obs = observer.new(W, k)
            local land = { t = 4, kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", flag = "", amount = 40 }
            land.school, land.swing, land.rage = 1, { t = 3.5 }, 12
            W.emit(land)
            local got = {}
            local function step(t)
                local first, last = obs.step(t)
                for i = first, last do
                    if obs.s.ev[i] == "@usable" and obs.s.t[i] > 0 then
                        got[#got + 1] = { t, obs.s.t[i], obs.s.a1[i], obs.s.a2[i] }
                    end
                end
            end
            step(4.0)
            step(4.2)
            W.emit({ t = 6, kind = "spell", src = W.ents[2], dst = mob, act = "WOUND", flag = "", amount = 900 })
            step(6.2)
            assert.are.same({ { 4.2, 4.1, 101, 1 }, { 6.2, 6.2, 102, 1 } }, got)
        end
    )
end)

describe("the world", function()
    it("takes health for every wound but our white swing's (ours at its land), and gives it for heals", function()
        local W = world.new(7)
        local us = W.add(entities.new({ guid = "Player-1", health = 500 }))
        local mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", health = 500 }))
        W.emit({ kind = "swing", src = mob, dst = us, hand = 1, act = "WOUND", amount = 40 })
        W.emit({ kind = "swing", src = us, dst = mob, hand = 1, act = "WOUND", amount = 30, ours = true })
        assert.are.equal(460, us.health)
        assert.are.equal(500, mob.health)
        W.emit({ kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", amount = 30 })
        W.emit({ kind = "spell", src = mob, dst = us, act = "HEAL", amount = 100 })
        assert.are.equal(470, mob.health)
        assert.are.equal(500, us.health)
    end)
end)
