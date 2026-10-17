-- tests/Virtual/harness/press_spec.lua (headless loop design §2.1.4-§2.1.5, §9): the world's runtime press and its
-- generic verbs, on the fake spec's spells (class-neutral).
local world = require("Virtual.harness.world")
local entities = require("Virtual.harness.entities")
local behaviours = require("Virtual.harness.behaviours")
local observer = require("Virtual.harness.observer")
local fs = require("Virtual.State.helpers.fake_spec")

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
            out[#out + 1] = table.concat({ s.ev[i], tostring(s.a1[i]), tostring(s.a2[i]) }, " ")
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
        local got = seen() -- our target targets us: the success fires on targettarget too
        assert.are.same({
            "UNIT_SPELLCAST_SUCCEEDED player Cast-1",
            "UNIT_SPELLCAST_SUCCEEDED targettarget Cast-1",
            "@truth 10 nil",
            "@truth 15 nil",
        }, { got[1], got[2], got[3], got[4] })
        local s = observer.observe(W)
        assert.are.equal(fs.SPENDER_C, s.a3[1])
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
        W.hit(us, mob, 50)
        assert.is_true(mob.dead)
        assert.are.equal(2, W.killAt)
        local got, at = seen(), nil
        for i, line in ipairs(got) do
            at = line == "@dead target true" and i or at
        end
        assert.are.same({
            "UNIT_HEALTH target nil",
            "@combat false nil",
            "@auraError target false",
            "PLAYER_REGEN_ENABLED nil nil",
        }, { got[at + 1], got[at + 2], got[at + 3], got[at + 4] })
    end)

    it("crits an instant hit at world.CRIT, doubled", function()
        setup()
        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
        local crits = 0
        for _ = 1, 400 do
            W.hit(us, mob, 100)
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
end)
