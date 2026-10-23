-- tests/Game/harness/observer_spec.lua (harness design §3.1 layer 4): each observer rule on a one-event true stream.
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local observer = require("Game.harness.observer")
local behaviours = require("Game.harness.behaviours")
local scenarios = require("Game.harness.scenarios")
local fake = require("Game.State.helpers.fake_api")

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
        assert.are.same({ 3, "UNIT_SPELLCAST_SENT", "player" }, { got[4][1], got[4][2], got[4][3] }) -- SENT first
        assert.are.same({ 3, "UNIT_SPELLCAST_SUCCEEDED", "player" }, { got[6][1], got[6][2], got[6][3] }) -- after tt's
        assert.is_number(got[6][5])
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
            local sent, ok =
                "UNIT_SPELLCAST_SENT UNIT_SPELLCAST_SENT ", "UNIT_SPELLCAST_SUCCEEDED UNIT_SPELLCAST_SUCCEEDED"
            assert.are.same({ -- SENT and the success each echoed on targettarget (our target targets us)
                sent .. ok .. " nameplate10 target0 PLAYER_SWING @current nameplate180 target80",
                sent .. "PLAYER_SWING nameplate10 target0 " .. ok .. " @current nameplate180 target80",
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
            { 5, "UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-1", observer.SPELLS.CAST, nil, 0 },
            { 5, "UNIT_SPELLCAST_SENT", "targettarget", "Mob", "Cast-1", observer.SPELLS.CAST, nil, 0 },
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

    it("shares one meter group between our hit swing and its proc in the same frame (DM §2)", function()
        setup()
        W.emit({ t = 5, kind = "swing", src = us, dst = mob, hand = 1, act = "WOUND", flag = "", amount = 30 })
        W.emit({ t = 5, kind = "proc", src = us, dst = mob, act = "WOUND", amount = 9, school = 32 })
        local s = observer.observe(W, setmetatable({ meter = true }, { __index = observer.DEFAULTS }))
        local n = 0
        for i = 1, s.n do
            if s.ev[i] == "DAMAGE_METER_COMBAT_SESSION_UPDATED" and s.a1[i] == 0 and s.a2[i] == 200 then
                n = n + 1
            end
        end
        assert.are.equal(1, n)
    end)

    it(
        "fires a @viewer edge 3-5 ms after an aura of ours under k.viewer (providers spec §4.2); a partner's none",
        function()
            setup(1)
            local partner = W.ents[3]
            W.emit({ t = 3, kind = "aura", dst = us, aura = 77, stacks = 1, expires = 13, duration = 10 })
            W.emit({ t = 4, kind = "aura", dst = partner, aura = 77, stacks = 1, expires = 14, duration = 10 })
            local s = observer.observe(W, setmetatable({ viewer = true }, { __index = observer.DEFAULTS }))
            local got = {}
            for i = 1, s.n do
                if s.ev[i] == "@viewer" then
                    got[#got + 1] = { s.t[i], s.a1[i], s.a2[i], s.a3[i] }
                end
            end
            assert.are.equal(1, #got)
            assert.is_true(got[1][1] >= 3.003 - 1e-9 and got[1][1] <= 3.005 + 1e-9)
            assert.are.same({ "player", 77, true }, { got[1][2], got[1][3], got[1][4] })
        end
    )

    it("steps to the batch's stream in 0.2 s steps, and draws nothing from the world's generator", function()
        local o = scenarios.oracle({ duration = 40, others = { "melee", "caster" } })
        local k = setmetatable({ usable = true }, { __index = observer.DEFAULTS })
        local batch = observer.observe(scenarios.build(o, 3), k)
        local W2 = scenarios.build(o, 3)
        local obs = observer.new(W2, k)
        local prev = -math.huge
        for t = 0, 50, 0.2 do
            local first, last = obs.step(t)
            for i = first, last do -- each step appends only up to its time, never before the last step's
                assert.is_true(obs.s.t[i] <= t + 1e-9 and obs.s.t[i] >= prev, i .. " at " .. t)
                prev = obs.s.t[i]
            end
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

    it(
        "answers a secret-free client under k.plain: power, target health, cooldown times plain, no aura error",
        function()
            setup()
            local k = setmetatable({ plain = true, usableDelay = 0, gcdSpell = 900 }, { __index = observer.DEFAULTS })
            local obs = observer.new(W, k) -- stepped as the world runs: each answer is the world's at its time
            W.emit({ t = 1.5, kind = "prepull" })
            obs.step(1.6)
            W.emit({ t = 2, kind = "pull" })
            -- our swing takes the health (the server's hit, 2026-10-22 kill-events capture); its row lands later
            W.emit({ t = 3.5, kind = "swing", src = us, dst = mob, hand = 1, act = "WOUND", amount = 40, ours = true })
            local land = { t = 4, kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", flag = "", amount = 40 }
            land.school, land.swing, land.rage = 1, { t = 3.5 }, 12
            W.emit(land)
            W.emit({
                t = 5,
                kind = "cast",
                src = us,
                dst = mob,
                spell = 9077,
                ids = { 9077, 9078 },
                cost = 10,
                cd = 6,
                gcd = 1.5,
            })
            local got = {}
            obs.step(math.huge)
            local s = obs.s
            for i = 1, s.n do
                local ev = s.ev[i]
                if ev == "@power" or ev == "@health" or ev == "@cooldown" or ev == "@auraError" then
                    got[#got + 1] = { s.t[i], ev, s.a1[i], s.a2[i], s.a3[i] }
                end
            end
            assert.are.same({
                { 0, "@power", 1, 0 },
                { 1.6, "@health", "target", 1000, 1000 },
                { 3.5, "@health", "target", 960, 1000 },
                { 4, "@power", 1, 12 },
                { 5, "@cooldown", 9077, 5, 6 },
                { 5, "@cooldown", 9078, 5, 6 },
                { 5, "@cooldown", 900, 5, 1.5 },
                { 5, "@power", 1, 2 },
                { 6.5, "@cooldown", 900, 0, 0 },
                { 11, "@cooldown", 9077, 0, 0 },
                { 11, "@cooldown", 9078, 0, 0 },
            }, got)
        end
    )
    describe("the 2026-10-22 client shapes (unit-registry spec §6.1)", function()
        local world = require("Game.harness.world")
        local entities = require("Game.harness.entities")
        local function fight(build, k)
            local W = world.new(1)
            local us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
            local mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", health = 1e9 }))
            us.target, mob.target = mob, us
            mob.avoid = { miss = 0, dodge = 0, parry = 0, block = 0 } -- every hit lands: the shapes, not the rolls
            build(W, us, mob)
            W.run(30)
            local s = observer.observe(W, setmetatable(k or {}, { __index = observer.DEFAULTS }))
            local out = {}
            for i = 1, s.n do
                if s.ev[i]:sub(1, 1) ~= "@" or s.ev[i] == "@casting" or s.ev[i] == "@health" then
                    out[#out + 1] = {
                        t = s.t[i],
                        ev = s.ev[i],
                        a1 = s.a1[i],
                        a2 = s.a2[i],
                        a3 = s.a3[i],
                        a4 = s.a4[i],
                        a5 = s.a5[i],
                        castT = s.castT[i],
                    }
                end
            end
            return out
        end
        local function find(out, ev, a1)
            for _, e in ipairs(out) do
                if e.ev == ev and (a1 == nil or e.a1 == a1) then
                    return e
                end
            end
        end

        it("sends SENT before a hard cast's START, with castBarIDs, echoed on targettarget", function()
            local out = fight(function(W, us)
                W.at(1, function()
                    W.press(us, "spender_p", { spell = "BOLT", cast = 1.5 })
                end)
            end)
            local sent, start = find(out, "UNIT_SPELLCAST_SENT", "player"), find(out, "UNIT_SPELLCAST_START", "player")
            assert.is_true(sent.t <= start.t and sent.a3 == start.a2)
            assert.is_truthy(tostring(start.a4):match("^Bar%-"))
            assert.is_truthy(find(out, "UNIT_SPELLCAST_START", "targettarget"))
        end)

        it("lands a projectile distance / velocity after its success, with its school and its castT", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.hitAt(us, mob, 15, 8, "spell", 1.5, 1)
                end)
            end)
            local row = find(out, "UNIT_COMBAT", "target")
            assert.are.same({ 2.5, 8, 1 }, { row.t, row.a5, row.castT })
        end)

        it("ticks a DoT in its school at its period from the application; a recast resets the schedule", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.dot(us, mob, 3, 4, 4, 64, "doti", 1)
                end)
                W.at(5, function()
                    W.dot(us, mob, 3, 4, 4, 64, "doti", 5)
                end)
            end)
            local ticks = {}
            for _, e in ipairs(out) do
                if e.ev == "UNIT_COMBAT" and e.a1 == "target" then
                    ticks[#ticks + 1] = math.floor(e.t + 0.5)
                    assert.are.equal(64, e.a5)
                end
            end
            assert.are.same({ 4, 8, 11, 14, 17 }, ticks) -- the first schedule's 7 never comes
        end)

        local function kill(out)
            return find(out, "PARTY_KILL"),
                find(out, "UNIT_DIED"),
                find(out, "PLAYER_TARGET_CHANGED"),
                find(out, "UNIT_COMBAT")
        end

        it(
            "kills by a white swing as measured: death at the swing, the clear 4 ms on, the row on the corpse later",
            function()
                local out = fight(function(W, us, mob)
                    W.at(1, function()
                        local sw = W.emit({
                            kind = "swing",
                            src = us,
                            dst = mob,
                            hand = 1,
                            act = "WOUND",
                            flag = "",
                            amount = 2e9,
                            school = 1,
                            ours = true,
                        })
                        W.at(1.456, function()
                            W.emit({
                                kind = "land",
                                src = us,
                                dst = mob,
                                hand = 1,
                                act = "WOUND",
                                flag = "",
                                amount = 2e9,
                                school = 1,
                                swing = sw,
                            })
                        end)
                    end)
                end)
                local pk, died, clear, row = kill(out)
                assert.are.same({ "Player-1", "Creature-1", 1 }, { pk.a1, pk.a2, pk.t })
                assert.is_true(math.abs(died.t - 1.002) < 1e-9 and math.abs(clear.t - 1.004) < 1e-9)
                assert.are.same({ 1.456, "softinteract" }, { row.t, row.a1 }) -- 452 ms after the clear, the corpse only
            end
        )

        it(
            "kills by a projectile: the clear, then the row 20 ms later on the plate, target and softinteract",
            function()
                local out = fight(function(W, us, mob)
                    W.at(1, function()
                        W.hitAt(us, mob, 2e9, 8, "spell", 1.5, 1)
                    end)
                end)
                local _, died, clear, row = kill(out)
                assert.is_true(died.t < clear.t and clear.t < row.t and math.abs(row.t - clear.t - 0.02) < 1e-9)
                assert.are.equal("nameplate1", row.a1)
            end
        )

        it("kills by an instant: its row in its frame, the clear 100 ms after it", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.emit({ kind = "spell", src = us, dst = mob, act = "WOUND", flag = "", amount = 2e9, school = 1 })
                end)
            end)
            local _, _, clear, row = kill(out)
            assert.is_true(row.t < clear.t and math.abs(clear.t - row.t - 0.1) < 1e-9)
        end)

        it("echoes every player cast event on targettarget while our target targets us", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.press(us, "spender_p", { spell = "BOLT", cast = 1.5 })
                end)
                W.at(2, function()
                    W.endCasts(us)
                end)
                W.at(3, function()
                    W.emit({ kind = "refused", src = us, spell = "BOLT" })
                end)
            end)
            for _, ev in ipairs({ "SENT", "START", "FAILED", "STOP", "INTERRUPTED" }) do
                assert.is_truthy(find(out, "UNIT_SPELLCAST_" .. ev, "targettarget"), ev)
            end
        end)

        it("stops a cast at a death with FAILED then STOP, then three INTERRUPTED with no castBarID", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.press(us, "spender_p", { spell = "BOLT", cast = 1.5 })
                end)
                W.at(2, function()
                    W.endCasts(us)
                end)
            end)
            local f, st = find(out, "UNIT_SPELLCAST_FAILED", "player"), find(out, "UNIT_SPELLCAST_STOP", "player")
            assert.are.equal(f.t, st.t)
            local n = 0
            for _, e in ipairs(out) do
                if e.ev == "UNIT_SPELLCAST_INTERRUPTED" and e.a1 == "player" then
                    n = n + 1
                    assert.is_nil(e.a5)
                end
            end
            assert.are.equal(3, n)
        end)

        it("churns a plate: removed while it still answers, re-added within the gap", function()
            local out = fight(function(W, us, mob)
                W.at(3, function()
                    W.emit({ kind = "plateOff", mob = mob })
                end)
                W.at(3.4, function()
                    W.emit({ kind = "plateOn", mob = mob })
                end)
            end)
            local off, on = find(out, "NAME_PLATE_UNIT_REMOVED"), find(out, "NAME_PLATE_UNIT_ADDED", "nameplate1")
            assert.are.same({ 3, "nameplate1" }, { off.t, off.a1 })
            assert.is_truthy(on)
        end)

        it("fans an outcome out to softenemy with Action Targeting on", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.hit(us, mob, 10, 1)
                end)
            end, { actionTargeting = true })
            assert.is_truthy(find(out, "UNIT_COMBAT", "softenemy"))
        end)

        it("pushes back our cast on a hit with pushback on: DELAYED, then the player's row 0.37 s later", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.press(us, "spender_p", { spell = "BOLT", cast = 1.5 })
                end)
                W.at(1.5, function()
                    W.emit({ kind = "spell", src = mob, dst = us, act = "WOUND", flag = "", amount = 5, school = 1 })
                end)
            end, { pushback = true })
            local d, row = find(out, "UNIT_SPELLCAST_DELAYED", "player"), find(out, "UNIT_COMBAT", "player")
            assert.are.same({ 1.5, "Bar-1" }, { d.t, d.a4 })
            assert.is_truthy(find(out, "UNIT_SPELLCAST_DELAYED", "targettarget"))
            assert.is_true(math.abs(row.t - 1.87) < 1e-9)
            local bars = {}
            for _, e in ipairs(out) do
                if e.ev == "@casting" and e.a1 then
                    bars[#bars + 1] = { e.t, e.a1, e.a2 }
                end
            end
            assert.are.same({ { 1, 1000, 2500 }, { 1.5, 1000, 3000 } }, bars) -- the bar moved by the pushback
        end)

        it("echoes our channel's stop on targettarget", function()
            local out = fight(function(W, us)
                W.at(1, function()
                    W.press(us, "spender_h", { spell = "CHAN", channel = { length = 2, tick = 1 } })
                end)
            end)
            assert.are.equal(3, find(out, "UNIT_SPELLCAST_CHANNEL_STOP", "targettarget").t)
        end)

        it("reads a secret-free client's target health at our swing, or at its row with healthAtSwing off", function()
            local function at(k)
                local out = fight(function(W, us, mob)
                    W.at(1, function()
                        local sw = W.emit({
                            kind = "swing",
                            src = us,
                            dst = mob,
                            hand = 1,
                            act = "WOUND",
                            flag = "",
                            amount = 10,
                            school = 1,
                            ours = true,
                        })
                        W.at(1.4, function()
                            W.emit({
                                kind = "land",
                                src = us,
                                dst = mob,
                                hand = 1,
                                act = "WOUND",
                                flag = "",
                                amount = 10,
                                school = 1,
                                swing = sw,
                            })
                        end)
                    end)
                end, k)
                local h = find(out, "@health")
                return { h.t, h.a2 }
            end
            assert.are.same({ 1, 1e9 - 10 }, at({ plain = true }))
            assert.are.same({ 1.4, 1e9 - 10 }, at({ plain = true, healthAtSwing = false }))
        end)

        it(
            "runs the detection suite's knobs: our scripted spells, no white swings, churn, extra mobs, a switch",
            function()
                local spells = {
                    { 2, "instant" },
                    { 4, "bolt" },
                    { 7, "doti" },
                    { 9, "ticks" },
                    { 11, "none" },
                    { 13, "bogus" },
                    { 15, "unmapped" },
                    { 15.5, "refused" },
                    { 17, "aoe" },
                    { 19, "chan" },
                }
                local s, W = scenarios.stream({
                    duration = 25,
                    noMelee = true,
                    spells = spells,
                    extraMobs = 1,
                    jitter = 0.05,
                    churn = { 5, 0.4 },
                    switchTo = { { 23, 2 } },
                    actionTargeting = true,
                }, 3)
                local seen = {}
                for i = 1, s.n do
                    local key = s.ev[i]
                        .. (
                            s.ev[i] == "UNIT_COMBAT" and (":" .. s.a5[i] .. ":" .. (s.castT[i] > 0 and "T" or "-"))
                            or ""
                        )
                    seen[key] = true
                end
                assert.is_nil(seen.PLAYER_SWING)
                -- the cast events' latency (jitter 0.05): each success at or after its truth, by at most the bound
                local truthT, j = {}, 0
                for _, ev in ipairs(W.truth) do
                    if ev.kind == "cast" and ev.src == W.ents[1] then
                        truthT[#truthT + 1] = ev.t
                    end
                end
                for i = 1, s.n do
                    if s.ev[i] == "UNIT_SPELLCAST_SUCCEEDED" and s.a1[i] == "player" then
                        j = j + 1
                        local d = s.t[i] - truthT[j]
                        assert.is_true(d >= 0 and d <= 0.05, "success " .. j .. " late by " .. d)
                    end
                end
                assert.are.equal(#truthT, j)
                assert.is_truthy(seen["UNIT_COMBAT:8:T"]) -- the bolt (or the ticks), in nature, with its success
                assert.is_truthy(seen["UNIT_COMBAT:64:T"]) -- the DoT's ticks and the channel's, in arcane
                assert.is_truthy(seen.NAME_PLATE_UNIT_REMOVED and seen.UNIT_SPELLCAST_FAILED)
                assert.is_truthy(seen.UNIT_SPELLCAST_CHANNEL_START)
                assert.are.equal(W.ents[3], W.ents[1].target) -- switched to the extra mob
                local aoe = 0
                for _, ev in ipairs(W.truth) do
                    aoe = aoe + ((ev.kind == "spell" and ev.t == 17 and ev.src == W.ents[1]) and 1 or 0)
                end
                assert.are.equal(2, aoe) -- our target and the extra mob with a plate
            end
        )
    end)
end)

-- The client facts several resources, the GCD and form shifts add (GCD kinds design §2.3), one rule per case.
describe("the observer's resources, GCD and forms", function()
    local W, us, mob
    local POOL, POINTS, GCD = 3, 4, 900 -- power types and the GCD spell, as bare numbers

    local function setup()
        W = world.new(7)
        us = W.add(entities.new({
            guid = "Player-1",
            weapons = { { 10, 10, 2.0 } },
            res = { [POOL] = { cur = 100, max = 100 }, [POINTS] = { cur = 0, max = 5 } },
            formSpeed = { [1] = 2.5 },
        }))
        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } }, health = 1e6 }))
        us.target = mob -- not on us: no targettarget rows
    end

    local function knobs(o)
        return setmetatable(o, { __index = observer.DEFAULTS })
    end

    -- The stream as "t ev a1 a2" lines (ops included, the time-0 answers left out), only the events `keep` names.
    local function lines(s, keep)
        local out = {}
        for i = 1, s.n do
            if s.t[i] > 0 and (not keep or keep[s.ev[i]]) then
                local a2 = rawequal(s.a2[i], fake.SECRET) and "SECRET" or tostring(s.a2[i])
                out[#out + 1] = table.concat({ s.t[i], s.ev[i], tostring(s.a1[i]), a2 }, " ")
            end
        end
        return out
    end

    it("fires the GCD flag's edges after the success or before it, by the press's order", function()
        setup()
        us.gcdOrder = 2
        W.t = 2
        W.press(us, "a", { spell = 11, gcd = 1.0 })
        us.gcdOrder = 1
        W.t = 4
        W.press(us, "a", { spell = 11, gcd = 1.0 })
        local keep = { UNIT_SPELLCAST_SUCCEEDED = true, ["@cooldown"] = true, SPELL_UPDATE_COOLDOWN = true }
        assert.are.same({
            "2 @cooldown 900 SECRET",
            "2 SPELL_UPDATE_COOLDOWN nil nil",
            "2 UNIT_SPELLCAST_SUCCEEDED player Cast-1",
            "3 @cooldown 900 nil", -- the end: no SPELL_UPDATE_COOLDOWN (Forever sends none)
            "4 UNIT_SPELLCAST_SUCCEEDED player Cast-2",
            "4 @cooldown 900 SECRET",
            "4 SPELL_UPDATE_COOLDOWN nil nil",
            "5 @cooldown 900 nil",
        }, lines(observer.observe(W, knobs({ gcdSpell = GCD })), keep))
    end)

    it("drops a cooldown's end that a restart on its instant supersedes (the end's float sum a ulp later)", function()
        setup()
        W.emit({ t = 0.1, kind = "cast", src = us, dst = mob, spell = 77, cd = 0.2 })
        W.emit({ t = 0.3, kind = "cast", src = us, dst = mob, spell = 77, cd = 0.2 }) -- 0.1 + 0.2 > 0.3
        local got = {}
        for _, l in ipairs(lines(observer.observe(W, knobs({ plain = true })), { ["@cooldown"] = true })) do
            got[#got + 1] = l:gsub("^(%S+)", function(x)
                return ("%.2f"):format(tonumber(x))
            end)
        end
        assert.are.same({
            "0.10 @cooldown 77 0.1",
            "0.30 @cooldown 77 0.3", -- the restart; the first end (0.30000000000000004) is gone
            "0.50 @cooldown 77 0",
        }, got)
    end)

    it("answers each power type by its mode: always, out of combat only, never", function()
        setup()
        local modes = { [POOL] = "ooc", [POINTS] = "always", [1] = "never" }
        local tokens = { [POOL] = "POOL", [POINTS] = "POINTS" }
        W.t = 1
        W.emit({ kind = "gain", src = us, pt = POOL, cost = 10 })
        W.emit({ kind = "pull" })
        W.t = 2
        W.emit({ kind = "gain", src = us, pt = POOL, cost = 20 })
        W.emit({ kind = "gain", src = us, pt = POINTS, rage = 1 })
        W.emit({ kind = "gain", src = us, rage = 5 })
        W.t = 3
        W.emit({ kind = "stop" })
        local s = observer.observe(W, knobs({ plainPower = modes, powerTokens = tokens }))
        assert.are.same({
            "1 @power 3 90",
            "1 UNIT_POWER_FREQUENT player POOL",
            "1 @power 3 nil", -- in combat: secret
            "2 @power 4 1",
            "2 UNIT_POWER_FREQUENT player POINTS",
            "3 @power 3 70", -- out of combat again
            "3 UNIT_POWER_FREQUENT player POOL",
        }, lines(s, { ["@power"] = true, UNIT_POWER_FREQUENT = true }))
    end)

    it("reads the regen rate out of combat with the caches, secret in combat; none without the read", function()
        setup()
        W.startRegen(us, { [POOL] = 10 })
        W.at(1, function()
            W.emit({ kind = "prepull" })
        end)
        W.at(2, function()
            W.emit({ kind = "pull" })
        end)
        W.at(5, function()
            W.emit({ kind = "stop" })
        end)
        W.run(5.5)
        assert.are.same(
            { "1 @regen 3 10", "2 @regen 3 nil", "5 @regen 3 10" },
            lines(observer.observe(W, knobs({})), { ["@regen"] = true })
        )
        assert.are.same({}, lines(observer.observe(W, knobs({ regenRead = false })), { ["@regen"] = true }))
    end)

    it("answers a cooldown finished early ready, plain to a secret-free client", function()
        for _, plain in ipairs({ false, true }) do
            setup()
            W.t = 2
            W.press(us, "a", { spell = 11, ids = { 11, 12 }, gcd = 0, cooldown = 10 })
            W.t = 3
            W.resetCooldown(us, "a", { 11, 12 })
            assert.is_nil(us.cdUntil.a)
            local s = observer.observe(W, knobs({ plain = plain }))
            local got = {}
            for i = 1, s.n do
                if s.ev[i] == "@cooldown" and s.t[i] == 3 then
                    got[#got + 1] = { s.a1[i], s.a2[i] }
                end
            end
            assert.are.same(plain and { { 11, 0 }, { 12, 0 } } or { { 11 }, { 12 } }, got)
            local later = 0 -- the reset cooldown's old end (12) is gone: no answer after it
            for i = 1, s.n do
                if s.ev[i] == "@cooldown" and s.t[i] > 3 then
                    later = later + 1
                end
            end
            assert.are.equal(0, later)
        end
    end)

    it("keeps our totem slots, one per slot, to their expiry; their reads plain out of combat, secret in it", function()
        for _, plain in ipairs({ false, true }) do
            setup()
            W.t = 1
            W.summonTotem(us, 2, 30, 9091)
            W.at(2, function()
                W.emit({ kind = "pull" })
            end)
            W.at(5, function()
                W.summonTotem(us, 4, 10, 9093)
                W.summonTotem(us, 2, 40, 9092) -- replaces slot 2's: the first one's expiry (31) is moot
            end)
            W.at(20, function()
                W.emit({ kind = "stop" })
            end)
            W.run(30)
            assert.is_nil(W.totem(us, 4))
            assert.are.same({ 9092, 5, 45 }, { W.totem(us, 2).spell, W.totem(us, 2).start, W.totem(us, 2).expires })
            W.run(50)
            assert.is_nil(W.totem(us, 2))
            local s = observer.observe(W, knobs({ plain = plain }))
            local got = {}
            for i = 1, s.n do
                if s.ev[i] == "@totem" and (s.a1[i] == 2 or s.a1[i] == 4) then
                    got[#got + 1] = { s.t[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i] }
                elseif s.ev[i] == "PLAYER_TOTEM_UPDATE" then
                    got[#got + 1] = { s.t[i], "update", s.a1[i] }
                end
            end
            local want = { { 1, 2, 9091, 1, 30 }, { 1, "update", 2 } }
            local function add(row)
                want[#want + 1] = row
            end
            if plain then
                add({ 5, 4, 9093, 5, 10 })
                add({ 5, "update", 4 })
                add({ 5, 2, 9092, 5, 40 })
                add({ 5, "update", 2 })
                add({ 15, 4, 0, 0, 0 })
                add({ 15, "update", 4 })
            else -- secret from the pull (each slot summoned into), each update's read too; plain again at the stop
                add({ 2, 2 })
                add({ 5, 4 })
                add({ 5, "update", 4 })
                add({ 5, 2 })
                add({ 5, "update", 2 })
                add({ 15, 4 })
                add({ 15, "update", 4 })
                add({ 20, 2, 9092, 5, 40 })
                add({ 20, 4, 0, 0, 0 })
            end
            add({ 45, 2, 0, 0, 0 })
            add({ 45, "update", 2 })
            assert.are.same(want, got)
        end
    end)

    it("reads an `fsr` pool's two rates out of combat: not casting, then casting", function()
        setup()
        W.startRegen(us, {}, 0.1, nil, { [POOL] = { 10, 2 } })
        W.at(1, function()
            W.emit({ kind = "prepull" })
        end)
        W.run(1.5)
        local s = observer.observe(W, knobs({}))
        local got = {}
        for i = 1, s.n do
            if s.ev[i] == "@regen" then
                got[#got + 1] = { s.a1[i], s.a2[i], s.a3[i] }
            end
        end
        assert.are.same({ { POOL, 12, 2 } }, got)
    end)

    it("fires a shift's success, then the form; the player's attack speed out of combat only", function()
        setup()
        W.t = 1
        W.press(us, "shift", { spell = 12, gcd = 1.5, shift = { form = 1 } })
        W.emit({ kind = "pull" })
        W.t = 3
        W.press(us, "shift", { spell = 13, gcd = 1.5, shift = { form = 0, speed = 1.0 } })
        local keep = { UNIT_SPELLCAST_SUCCEEDED = true, ["@form"] = true, UPDATE_SHAPESHIFT_FORM = true }
        keep["@attackSpeed"] = true
        assert.are.same({
            "1 UNIT_SPELLCAST_SUCCEEDED player Cast-1",
            "1 @form 1 nil",
            "1 UPDATE_SHAPESHIFT_FORM nil nil",
            "1 @attackSpeed 2.5 nil", -- out of combat: the form's period, with the damage cache
            "3 UNIT_SPELLCAST_SUCCEEDED player Cast-2",
            "3 @form 0 nil",
            "3 UPDATE_SHAPESHIFT_FORM nil nil", -- in combat: no read
        }, lines(observer.observe(W, knobs({ playerSpeed = true })), keep))
    end)

    it("answers usability against each rung's own type, the client's view a gain late", function()
        setup()
        local function pool(_, _, _, view)
            return view[POOL] >= 60, view[POOL] < 60
        end
        W.t = 1
        W.emit({ kind = "gain", src = us, pt = POOL, cost = 50 })
        W.t = 2
        W.emit({ kind = "gain", src = us, pt = POOL, rage = 20 })
        local s = observer.observe(W, knobs({ usable = { { 21, pool } }, usableDelay = 0.1 }))
        assert.are.same({ "1 @usable 21 2", "2.1 @usable 21 1" }, lines(s, { ["@usable"] = true }))
    end)

    it(
        "answers a gain in the frame of a spend with the spend, either order (an avoid's refund, a swing's rage)",
        function()
            setup()
            local function pool(_, _, _, view)
                return view[POOL] >= 60, view[POOL] < 60
            end
            W.t = 1
            W.emit({ kind = "gain", src = us, pt = POOL, cost = 50 }) -- 100 - 50: short alone
            W.t = 1 + 1e-6 -- the replay's next line of one timestamp
            W.emit({ kind = "gain", src = us, pt = POOL, rage = 20 }) -- its refund in the same frame: 70, never short
            W.t = 3 - 1e-6
            W.emit({ kind = "gain", src = us, pt = POOL, rage = 20 }) -- 90, then the spend in the same frame: 40, short
            W.t = 3
            W.emit({ kind = "gain", src = us, pt = POOL, cost = 50 })
            local s = observer.observe(W, knobs({ usable = { { 21, pool } }, usableDelay = 0.1 }))
            assert.are.same({ "3 @usable 21 2" }, lines(s, { ["@usable"] = true })) -- no stale short at 1, none late at 3
        end
    )

    it("answers usability with our form as of the answer's time, a shift's form and resource change as one", function()
        setup()
        local function pool(_, now, _, view) -- needs form 1: short below 60 there, not usable elsewhere
            return now.form == 1 and view[POOL] >= 60, now.form == 1 and view[POOL] < 60
        end
        W.t = 0.5
        W.emit({ kind = "prepull" })
        W.t = 1
        W.emit({ kind = "gain", src = us, pt = POOL, cost = 30 }) -- 70 in form 0: not usable; no transient yes at 3
        W.t = 3
        W.press(us, "shift", { spell = 12, gcd = 1.5, shift = { form = 1, onEnter = { [POOL] = "zero" } } })
        local s = observer.observe(W, knobs({ usable = { { 21, pool } }, usableDelay = 0 }))
        assert.are.same({ "3 @usable 21 2" }, lines(s, { ["@usable"] = true }))
    end)
end)

describe("the world", function()
    it(
        "takes health for every wound but our white swing's with W.hitAtSwing off (ours at its land), and heals",
        function()
            local W = world.new(7)
            W.hitAtSwing = false
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
        end
    )

    it("takes our white wound at the swing by default (W.hitAtSwing: the server's hit)", function()
        local W = world.new(7)
        local us = W.add(entities.new({ guid = "Player-1", health = 500 }))
        local mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", health = 500 }))
        W.emit({ kind = "swing", src = us, dst = mob, hand = 1, act = "WOUND", amount = 30, ours = true })
        assert.are.equal(470, mob.health)
        W.emit({ kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", amount = 30 })
        assert.are.same({ 470, 500 }, { mob.health, us.health })
    end)
end)
