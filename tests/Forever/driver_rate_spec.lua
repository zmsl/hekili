-- tests/Forever/driver_rate_spec.lua (perf phase 2, items 2.1a and 2.4): the rate of Hekili.Update through the real
-- engine frame (Engine/Driver.lua's OnUpdate) at 60 frames a second on the fake clock. Traces call Update directly and
-- bypass the Driver, so this spec is the proof of what the two default-on switches do. Update is a counter here: the
-- spec measures how often the Driver starts one, not what one does.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local DT = 1 / 60

describe("the Driver's update rate", function()
    local H, f, runs, perf

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        f, perf = H.ns.EngineFrame, H.Hekili.DB.profile.performance
        H.Hekili.Update = function()
            runs = runs + 1
        end
        runs = 0
    end)

    -- Updates a second over `seconds` of frames; `perFrame(i)` runs before frame i.
    local function rate(seconds, perFrame)
        local frames = math.floor(seconds * 60 + 0.5)
        runs = 0
        for i = 1, frames do
            H.ctl.now = H.ctl.now + DT
            if perFrame then
                perFrame(i)
            end
            f.__scripts.OnUpdate(f, DT)
        end
        return runs / seconds
    end

    -- A fight: an ordinary force every few frames keeps the wait at 0.2 s (the combat rate), and `auraRate` UNIT_AURAs
    -- a second arrive on top of it.
    local function fight(auraRate)
        local every = auraRate > 0 and math.floor(60 / auraRate + 0.5)
        return rate(20, function(i)
            if i % 3 == 0 then
                H.Hekili:ForceUpdate("TEST")
            end
            if every and i % every == 0 then
                H.Fire("UNIT_AURA", "player")
            end
        end)
    end

    describe("2.1a, the aura force", function()
        it("on (the default): aura events leave the rate where the 0.2 s wait puts it, at any aura rate", function()
            assert.is_true(perf.auraForceOrdinary)
            local base = fight(0)
            assert.is_true(base > 4 and base <= 5, "the wait's rate: " .. base)
            assert.is_true(math.abs(fight(4) - base) <= 0.1)
            assert.is_true(math.abs(fight(20) - base) <= 0.1)
        end)

        it("off: each aura event pushes the timer on, as before the switch", function()
            perf.auraForceOrdinary = false
            local base = fight(0)
            local at4, at20 = fight(4), fight(20)
            assert.is_true(at4 > base + 1, "at 4 events/s: " .. at4 .. " against " .. base)
            assert.is_true(at20 > base * 2, "at 20 events/s: " .. at20 .. " against " .. base)
        end)

        it("on: an aura event alone still gets its update within the 0.2 s wait", function()
            rate(1)
            f.refreshTimer = 0
            H.Fire("UNIT_AURA", "player")
            assert.is_true(f.criticalUpdate)
            assert.are.equal(0, rate(0.15) * 0.15)
            assert.are.equal(1, rate(0.1) * 0.1)
        end)

        it("on: a target change still pushes the timer on", function()
            f.refreshTimer = 0
            H.Fire("PLAYER_TARGET_CHANGED")
            assert.is_true(f.refreshTimer >= 0.1)
        end)
    end)

    describe("2.4, the idle gate", function()
        local SECRET = require("Game.State.helpers.fake_api").SECRET

        -- The rate at rest, after the first update has seen the conditions.
        local function rest()
            rate(2)
            return rate(30)
        end

        before_each(function()
            H.ctl.friendly.target = true -- what UnitCanAttack answers with no target, or a friendly one
        end)

        it("on (the default), out of combat with no hostile target: one update each 1.5 s", function()
            assert.is_true(perf.idleGate)
            local r = rest()
            assert.is_true(r > 0.6 and r <= 2 / 3, "idle rate: " .. r)
        end)

        it("off: every 0.5 s, as before the switch", function()
            perf.idleGate = false
            local r = rest()
            assert.is_true(r > 1.8 and r <= 2, "rest rate: " .. r)
        end)

        it("a hostile target, combat, or a secret answer each keep the 0.5 s rest rate", function()
            H.ctl.friendly.target = nil
            local hostile = rest()
            assert.is_true(hostile > 1.8 and hostile <= 2, "with a hostile target: " .. hostile)
            H.ctl.friendly.target = true
            H.ctl.combat = true
            assert.are.equal(hostile, rest())
            H.ctl.combat = false
            H.ctl.friendly.target = SECRET
            assert.are.equal(hostile, rest())
        end)

        it("a target change wakes it within the 0.2 s wait, and the rest rate follows the new target", function()
            rest()
            f.refreshTimer = 0
            H.ctl.friendly.target = nil
            H.Fire("PLAYER_TARGET_CHANGED")
            assert.are.equal(1, rate(0.25) * 0.25)
            local r = rate(30)
            assert.is_true(r > 1.8 and r <= 2, "after the wake: " .. r)
        end)

        it("a cast wakes it within the 0.2 s wait, and it goes back to idle", function()
            rest()
            f.refreshTimer = 0
            H.Fire("UNIT_SPELLCAST_SENT", "player", "nobody", "cast-1", ww.IDS.battle_shout[1])
            assert.are.equal(1, rate(0.25) * 0.25)
            assert.are.equal(0, rate(1))
        end)

        it("entering combat wakes it within the 0.2 s wait", function()
            rest()
            f.refreshTimer = 0
            H.ctl.combat = true
            H.Fire("PLAYER_REGEN_DISABLED")
            assert.are.equal(1, rate(0.25) * 0.25)
            local r = rate(30)
            assert.is_true(r > 1.8 and r <= 2, "in combat: " .. r)
        end)
    end)

    it("each option writes the profile, on by default", function()
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        local args = H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
        for _, name in ipairs({ "auraForceOrdinary", "idleGate" }) do
            assert.is_true(args[name].get())
            args[name].set(nil, false)
            assert.is_false(perf[name])
            assert.is_false(args[name].get())
        end
    end)
end)
