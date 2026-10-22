-- tests/Game/harness/press_spec.lua (headless loop design §2.1.4-§2.1.5, §9): the world's runtime press and its
-- generic verbs, on the fake spec's spells (class-neutral).
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local behaviours = require("Game.harness.behaviours")
local observer = require("Game.harness.observer")
local fs = require("Game.State.helpers.fake_spec")
local fake = require("Game.State.helpers.fake_api")

describe("the world's press", function()
    local W, us, mob

    local function setup()
        W = world.new(5)
        us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } }, health = 1e6 }))
        us.target, mob.target = mob, us
        us.power = 20
    end

    -- The client events of the world so far, as "ev a1 a2" strings (ops included, the initial answers left out).
    local function seen()
        local s, out = observer.observe(W), {}
        for i = 1, s.n do
            local a2 = rawequal(s.a2[i], fake.SECRET) and "SECRET" or tostring(s.a2[i])
            out[#out + 1] = table.concat({ s.ev[i], tostring(s.a1[i]), a2 }, " ")
        end
        return out
    end

    it("refuses a press for the GCD, the cooldown, the cost and a requirement, changing nothing", function()
        setup()
        local p = { spell = fs.SPENDER_A, cost = 10, cooldown = 6, gcd = 1.5 }
        W.t = 10
        assert.is_true(W.press(us, "spender_a", p))
        W.t = 11 -- the GCD runs to 11.5
        assert.are.same({ false, "gcd" }, { W.press(us, "spender_b", { spell = fs.SPENDER_B, cost = 5 }) })
        W.t = 12 -- off the GCD, on the cooldown until 16
        assert.are.same({ false, "cooldown" }, { W.press(us, "spender_a", p) })
        assert.are.same({ false, "cost" }, { W.press(us, "spender_b", { spell = fs.SPENDER_B, cost = 15 }) })
        local why = function()
            return false, "phase"
        end
        assert.are.same(
            { false, "requires:phase" },
            { W.press(us, "spender_b", { spell = fs.SPENDER_B, cost = 5, requires = why }) }
        )
        assert.are.same({ 10, 11.5, 16 }, { us.power, us.gcdUntil, us.cdUntil.spender_a })
        assert.is_nil(us.cdUntil.spender_b)
        local casts = 0
        for _, ev in ipairs(W.truth) do
            casts = casts + (ev.kind == "cast" and 1 or 0)
        end
        assert.are.equal(1, casts)
    end)

    it("accepts a press: spends, starts the GCD and cooldown, emits the cast with its spell ID as is", function()
        setup()
        W.t = 3
        local hit = 0
        local p = {
            spell = fs.SPENDER_C,
            cost = 10,
            cooldown = 6,
            effect = function(w, e)
                hit = hit + 1
                w.gain(e, 5)
            end,
        }
        assert.is_true(W.press(us, "spender_c", p))
        assert.are.same({ 15, 4.5, 9, 1 }, { us.power, us.gcdUntil, us.cdUntil.spender_c, hit })
        -- SENT then the success, each echoed on targettarget (our target targets us); the cooldown's flag (times secret)
        local got = seen()
        assert.are.same({
            "UNIT_SPELLCAST_SENT player Mob",
            "UNIT_SPELLCAST_SENT targettarget Mob",
            "UNIT_SPELLCAST_SUCCEEDED player Cast-1",
            "UNIT_SPELLCAST_SUCCEEDED targettarget Cast-1",
            "@cooldown " .. fs.SPENDER_C .. " SECRET",
            "SPELL_UPDATE_COOLDOWN nil nil",
            "@truth 10 nil",
            "@truth 15 nil",
        }, { got[1], got[2], got[3], got[4], got[5], got[6], got[7], got[8] })
        local s = observer.observe(W)
        assert.are.same({ fs.SPENDER_C, fs.SPENDER_C }, { s.a4[1], s.a3[3] }) -- SENT's and the success's
    end)

    it("queues an on-next-swing press (IsCurrentSpell) and pays it at the swing; one queued at a time", function()
        setup()
        behaviours.melee({ land = observer.lag(), phase = { 2, 9 } })(W, us)
        W.run(1)
        local p = { spell = fs.SPENDER_B, cost = 15, offGcd = true, onNextSwing = true, amount = { 70, 70 } }
        assert.is_true(W.press(us, "spender_b", p))
        assert.are.same({ false, "queued" }, { W.press(us, "spender_b", p) })
        assert.are.equal(20, us.power) -- paid at the swing, not the press
        W.run(2.5)
        assert.are.equal(5, us.power)
        local got = seen()
        assert.are.equal("@current " .. fs.SPENDER_B .. " true", got[1])
        local last
        for _, line in ipairs(got) do
            if line:match("^@current") then
                last = line
            end
        end
        assert.are.equal("@current " .. fs.SPENDER_B .. " false", last)
    end)

    it(
        "drops a queued strike the power no longer covers at the swing: unqueued, a white swing, nothing paid",
        function()
            setup()
            behaviours.melee({ land = observer.lag(), phase = { 2, 9 } })(W, us)
            W.run(1)
            assert.is_true(
                W.press(us, "spender_b", { spell = fs.SPENDER_B, cost = 15, offGcd = true, onNextSwing = true })
            )
            us.power = 10 -- spent elsewhere before the swing
            W.run(2.5)
            assert.are.same({ 10, nil }, { us.power, us.queued })
            local kinds = {}
            for _, ev in ipairs(W.truth) do
                kinds[ev.kind] = (kinds[ev.kind] or 0) + 1
            end
            assert.are.same({ 1, nil }, { kinds.unqueue, kinds.strike })
        end
    )

    it(
        "rolls the same-ms avoid from the client-detail generator: on every swing at 1, W.rng's draws unchanged",
        function()
            local function swings(sameMs)
                setup()
                behaviours.melee({ land = observer.lag(), phase = { 2, 9 }, sameMs = sameMs })(W, us)
                W.run(20)
                local n, same = 0, 0
                for _, ev in ipairs(W.truth) do
                    if ev.kind == "swing" and ev.src == us then
                        n, same = n + 1, same + (ev.sameMs and 1 or 0)
                    end
                end
                return n, same, W.rng.next()
            end
            local n, same, draw = swings(1)
            assert.are.same({ n, 0, draw }, { swings(nil) })
            assert.is_true(n > 0 and same == n, same .. " of " .. n)
        end
    )

    it("puts an aura on the clock: ours on the player plain until its expiry; a refresh keeps it up", function()
        setup()
        W.t = 1
        W.applyAura(us, 501, 10)
        W.at(6, function()
            W.applyAura(us, 501, 10)
        end)
        W.applyAura(mob, 502, 30, 1, 5)
        W.applyAura(mob, 502, 30, 1, 5)
        W.run(15)
        assert.are.equal(2, mob.auras[502].stacks)
        assert.is_table(us.auras[501]) -- the refresh at 6 runs to 16
        W.run(17)
        assert.is_nil(us.auras[501])
        local s, lines = observer.observe(W), {}
        for i = 1, s.n do
            if s.ev[i] == "@aura" then
                lines[#lines + 1] = { s.t[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i] }
            end
        end
        assert.are.same({
            { 1, "player", 501, 1, 11 },
            { 1, "target", 502, 1, 31 },
            { 1, "target", 502, 2, 31 },
            { 6, "player", 501, 1, 16 },
            { 16, "player", 501, 0, 0 },
        }, lines)
    end)

    it("ends the fight at a kill: the target dead, out of combat when no attacker is left", function()
        setup()
        mob.health = 30
        W.t = 2
        W.emit({ kind = "pull" })
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        W.hit(us, mob, 50, 1)
        assert.is_true(mob.dead)
        assert.are.equal(2, W.killAt)
        local got, at = seen(), nil
        for i, line in ipairs(got) do
            at = line == "@dead target true" and i or at
        end
        assert.are.same({ -- the clear (an instant kill's: 100 ms after its row), then out of combat 1 s on
            "@guid target nil",
            "@guid softinteract Creature-1",
            "PLAYER_TARGET_CHANGED nil nil",
            "UNIT_HEALTH target nil",
            "@combat false nil",
            "@auraError target false",
            "PLAYER_REGEN_ENABLED nil nil",
        }, { got[at + 1], got[at + 2], got[at + 3], got[at + 4], got[at + 5], got[at + 6], got[at + 7] })
    end)

    it("an avoided press: the target's avoid, then its `refund` share of the cost back (a wound gives none)", function()
        setup()
        W.t = 3
        mob.avoid = { miss = 0, dodge = 1, parry = 0 }
        local p = {
            spell = fs.SPENDER_C,
            cost = 10,
            refund = 0.8,
            effect = function(w, e)
                w.hit(e, e.target, 40, 1)
                w.hit(e, e.target, 40, 1) -- a second outcome of one press: one refund
            end,
        }
        assert.is_true(W.press(us, "spender_c", p))
        assert.are.equal(18, us.power) -- 20 - 10 + 8
        local n, success, first = 0, nil, nil
        for i, line in ipairs(seen()) do
            success = success or (line == "UNIT_SPELLCAST_SUCCEEDED player Cast-1" and i or nil)
            if line == "UNIT_COMBAT target DODGE" then
                n, first = n + 1, first or i
            end
        end
        assert.are.equal(2, n)
        assert.is_true(success < first) -- the cast's success, then its outcome
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        W.t = 10
        assert.is_true(W.press(us, "spender_c", p))
        assert.are.equal(8, us.power)
        W.t = 20
        assert.is_true(W.press(us, "spender_c", { spell = fs.SPENDER_C, cost = 5, effect = p.effect })) -- no refund
        assert.are.equal(3, us.power)
    end)

    it("rolls each press's own avoids (wowsims's tables): melee, a miss only, a spell's miss, none", function()
        setup()
        mob.avoid = { miss = 0.2, dodge = 0.2, parry = 0.2, spellMiss = 0.5 }
        local function tally(set)
            local n = {}
            for _ = 1, 600 do
                local act = W.rollOutcome(mob, set)
                n[act] = (n[act] or 0) + 1
            end
            return n
        end
        local melee, miss, spell, none = tally(nil), tally("miss"), tally("spell"), tally("none")
        assert.is_true(melee.DODGE > 60 and melee.PARRY > 60 and melee.MISS > 60)
        assert.are.same({ nil, nil }, { miss.DODGE, miss.PARRY })
        assert.is_true(miss.MISS > 60 and miss.MISS < 180)
        assert.are.same({ nil, nil }, { spell.DODGE, spell.PARRY })
        assert.is_true(spell.MISS > 240) -- the victim's spellMiss
        assert.are.same({ 600 }, { none.WOUND })
    end)

    it("a hit with no amount shows no outcome when it lands, only its avoid", function()
        setup()
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        local n = #W.truth
        assert.are.equal("WOUND", W.hit(us, mob, nil, 1).act)
        assert.are.equal(n, #W.truth)
        mob.avoid = { miss = 1, dodge = 0, parry = 0 }
        assert.are.equal("MISS", W.hit(us, mob, nil, 1).act)
        assert.are.equal("MISS", W.truth[#W.truth].act)
    end)

    it("an avoided finisher keeps its points (spends them all only when it lands)", function()
        setup()
        us.res[4] = { cur = 3, max = 5 }
        mob.avoid = { miss = 1, dodge = 0, parry = 0 }
        local p = {
            spell = fs.SPENDER_C,
            points = { 4, "all" },
            effect = function(w, e)
                w.hit(e, e.target, 40, 1)
            end,
        }
        W.t = 3
        assert.is_true(W.press(us, "spender_c", p))
        assert.are.equal(3, us.res[4].cur)
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        W.t = 10
        assert.is_true(W.press(us, "spender_c", p))
        assert.are.equal(0, us.res[4].cur)
    end)

    it("a queued strike rolls its press's avoids at its swing and gives back its refund share", function()
        setup()
        mob.avoid = { miss = 0, dodge = 1, parry = 0 }
        behaviours.melee({ land = observer.lag(), phase = { 2, 9 } })(W, us)
        W.run(1)
        local p = {
            spell = fs.SPENDER_B,
            cost = 15,
            offGcd = true,
            onNextSwing = true,
            amount = { 70, 70 },
            outcomes = "melee",
            refund = 0.8,
        }
        assert.is_true(W.press(us, "spender_b", p))
        W.run(2.5)
        assert.are.equal(17, us.power) -- 20 - 15 + 12
        local strike
        for _, ev in ipairs(W.truth) do
            strike = ev.kind == "strike" and ev or strike
        end
        assert.are.same({ "DODGE", 0 }, { strike.act, strike.amount })
        assert.is_not_nil(us.avoidAt.DODGE)
    end)

    it("crits an instant hit at world.CRIT, doubled", function()
        setup()
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        local crits = 0
        for _ = 1, 400 do
            W.hit(us, mob, 100, 1)
            local ev = W.truth[#W.truth]
            crits = crits + (ev.flag == "CRITICAL" and 1 or 0)
            assert.are.equal(ev.flag == "CRITICAL" and 200 or 100, ev.amount)
        end
        assert.is_true(world.CRIT > 0)
        assert.is_true(math.abs(crits / 400 - world.CRIT) < 0.05, tostring(crits))
    end)

    it("completes a cast-time press after its cast: spent and cast then, other presses refused meanwhile", function()
        setup()
        W.t = 1
        local done = 0
        local p = {
            spell = fs.SPENDER_A,
            cost = 10,
            cast = 1.5,
            effect = function()
                done = done + 1
            end,
        }
        assert.is_true(W.press(us, "spender_a", p))
        assert.are.same({ 20, 0 }, { us.power, done })
        assert.are.same({ false, "casting" }, { W.press(us, "spender_b", { spell = fs.SPENDER_B, offGcd = true }) })
        W.run(2.5)
        assert.are.same({ 10, 1 }, { us.power, done })
        local cast = W.truth[#W.truth]
        assert.are.same({ "cast", 2.5 }, { cast.kind, cast.t })
    end)

    -- Our cast and channel events and their answers, as "t ev a1 a2 a3" strings (central fix 22, gap BC).
    local function casts()
        local s, out = observer.observe(W, setmetatable({ gcdSpell = 61304 }, { __index = observer.DEFAULTS })), {}
        for i = 1, s.n do
            local ev = s.ev[i]
            if
                (ev:match("^UNIT_SPELLCAST") and ev ~= "UNIT_SPELLCAST_SENT" and s.a1[i] == "player")
                or ev == "@casting"
                or ev == "@channel"
            then
                out[#out + 1] = table.concat(
                    { ("%.2f"):format(s.t[i]), ev, tostring(s.a1[i]), tostring(s.a2[i]), tostring(s.a3[i]) },
                    " "
                )
            end
        end
        return out
    end

    describe("a channel (channel = { length, tick })", function()
        local ticks
        local function channel()
            ticks = {}
            return {
                spell = fs.SPENDER_C,
                cost = 10,
                gcd = 1.5,
                channel = {
                    length = 3,
                    tick = 1,
                    gain = { 3, 5 }, -- each tick's resource gain (a pool of type 3)
                    effect = function(W2, _, _, n)
                        ticks[#ticks + 1] = { n, W2.t }
                    end,
                },
            }
        end

        it("opens with its answer, CHANNEL_START then SUCCEEDED, ticks every second and stops at its end", function()
            setup()
            us.res[3] = { cur = 0, max = 100 }
            W.t = 1
            assert.is_true(W.press(us, "spender_c", channel()))
            assert.are.equal(10, us.power) -- paid at the start
            W.t = 2.6
            assert.are.same({ false, "casting" }, { W.press(us, "spender_b", { spell = fs.SPENDER_B, offGcd = true }) })
            W.run(10)
            assert.are.same({ { 1, 2 }, { 2, 3 }, { 3, 4 } }, ticks)
            assert.are.equal(15, us.res[3].cur)
            local id = tostring(fs.SPENDER_C)
            assert.are.same({
                "1.00 @channel 1000 4000 nil",
                "1.00 UNIT_SPELLCAST_CHANNEL_START player Cast-1 " .. id,
                "1.00 UNIT_SPELLCAST_SUCCEEDED player Cast-1 " .. id,
                "4.00 @channel nil nil nil",
                "4.00 UNIT_SPELLCAST_CHANNEL_STOP player Cast-1 " .. id,
            }, casts())
            assert.is_true(W.press(us, "spender_b", { spell = fs.SPENDER_B, offGcd = true }))
        end)

        it("is clipped by a press declaring `clip`: stopped then, no later tick, the new press cast", function()
            setup()
            us.res[3] = { cur = 0, max = 100 }
            W.t = 1
            assert.is_true(W.press(us, "spender_c", channel()))
            W.run(2.5)
            assert.is_true(W.press(us, "spender_b", { spell = fs.SPENDER_B, gcd = 1.5, clip = true }))
            W.run(10)
            assert.are.same({ { 1, 2 } }, ticks)
            local id, b = tostring(fs.SPENDER_C), tostring(fs.SPENDER_B)
            assert.are.same({
                "1.00 @channel 1000 4000 nil",
                "1.00 UNIT_SPELLCAST_CHANNEL_START player Cast-1 " .. id,
                "1.00 UNIT_SPELLCAST_SUCCEEDED player Cast-1 " .. id,
                "2.50 @channel nil nil nil",
                "2.50 UNIT_SPELLCAST_CHANNEL_STOP player Cast-1 " .. id,
                "2.50 UNIT_SPELLCAST_SUCCEEDED player Cast-2 " .. b,
            }, casts())
        end)
    end)

    it("starts a hard cast with UNIT_SPELLCAST_START and its UnitCastingInfo, the GCD from the start", function()
        setup()
        W.t = 1
        assert.is_true(W.press(us, "spender_a", { spell = fs.SPENDER_A, cost = 10, cast = 1.5, gcd = 1.5 }))
        W.run(5)
        local a = tostring(fs.SPENDER_A)
        assert.are.same({
            "1.00 @casting 1000 2500 nil",
            "1.00 UNIT_SPELLCAST_START player Cast-1 " .. a,
            "2.50 @casting nil nil nil",
            "2.50 UNIT_SPELLCAST_SUCCEEDED player Cast-1 " .. a,
            "2.50 UNIT_SPELLCAST_STOP player Cast-1 " .. a,
        }, casts())
        local gcd = {}
        local s = observer.observe(W, setmetatable({ gcdSpell = 61304 }, { __index = observer.DEFAULTS }))
        for i = 1, s.n do
            if s.ev[i] == "@cooldown" and s.a1[i] == 61304 and s.a2[i] ~= nil then
                gcd[#gcd + 1] = s.t[i]
            end
        end
        assert.are.same({ 1 }, gcd) -- the GCD's flag rises at the cast's start
    end)

    -- Fix 31 G3: a fight's end stops our cast in progress, as the client's interrupt on a dead target does, so no
    -- stale cast start outlives the fight (a later instant cast of it would take that start as its GCD's).
    it("interrupts a hard cast in progress when our target dies: no success, other presses free", function()
        setup()
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        local done = 0
        local p = { spell = fs.SPENDER_A, cost = 10, cast = 1.5, gcd = 1.5 }
        p.effect = function()
            done = done + 1
        end
        W.t = 1
        assert.is_true(W.press(us, "spender_a", p))
        W.run(2)
        W.hit(us, mob, 2e6, 1)
        assert.is_true(mob.dead)
        assert.is_true(W.press(us, "spender_b", { spell = fs.SPENDER_B, offGcd = true }))
        W.run(5)
        assert.are.equal(0, done)
        local a = tostring(fs.SPENDER_A)
        assert.are.same({
            "1.00 @casting 1000 2500 nil",
            "1.00 UNIT_SPELLCAST_START player Cast-1 " .. a,
            "2.00 @casting nil nil nil",
            "2.00 UNIT_SPELLCAST_FAILED player Cast-1 " .. a,
            "2.00 UNIT_SPELLCAST_STOP player Cast-1 " .. a,
            "2.00 UNIT_SPELLCAST_SUCCEEDED player Cast-2 " .. tostring(fs.SPENDER_B),
            "2.15 UNIT_SPELLCAST_INTERRUPTED player Cast-1 " .. a,
            "2.15 UNIT_SPELLCAST_INTERRUPTED player Cast-1 " .. a,
            "2.15 UNIT_SPELLCAST_INTERRUPTED player Cast-1 " .. a,
        }, casts())
    end)

    it("stops a channel in progress when the loop leaves the world (W.endCasts)", function()
        setup()
        W.t = 1
        assert.is_true(
            W.press(us, "spender_c", { spell = fs.SPENDER_C, gcd = 1.5, channel = { length = 3, tick = 1 } })
        )
        W.run(2)
        W.endCasts(us)
        W.run(10)
        local c = tostring(fs.SPENDER_C)
        assert.are.same({
            "1.00 @channel 1000 4000 nil",
            "1.00 UNIT_SPELLCAST_CHANNEL_START player Cast-1 " .. c,
            "1.00 UNIT_SPELLCAST_SUCCEEDED player Cast-1 " .. c,
            "2.00 @channel nil nil nil",
            "2.00 UNIT_SPELLCAST_CHANNEL_STOP player Cast-1 " .. c,
        }, casts())
    end)
end)
