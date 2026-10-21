-- tests/Forever/channel_engine_spec.lua (central fix 22, gap BC): the engine's own channel and cast handling on the
-- harness's events. The world's channel press (W.press `channel`) and hard cast, through the observer and the drive's
-- answers, reach a booted instance: mid-channel the simulation reads `buff.casting` and `channel_remains` from the
-- queued CHANNEL_FINISH, after CHANNEL_STOP neither; mid-cast `buff.casting` from the queued CAST_FINISH. A Warrior
-- booted Undead: Cannibalize (Hekili_Shared's race pack) is the channel, Slam the hard cast.
local headless = require("Game.harness.headless")
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local observer = require("Game.harness.observer")
local drive = require("Game.harness.drive")
local ww = require("Forever.helpers.warrior_world")

local CANNIBALIZE = 20577

describe("the engine on the harness's channel and cast events", function()
    local H, st, W, us, s, fired

    before_each(function()
        local c = ww.character()
        c.race = "Scourge"
        c.known[#c.known + 1] = CANNIBALIZE
        H = headless.new({ character = c, pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        st = H.Hekili.State
        W = world.new(1)
        us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
        local mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 1, 1, 2 } }, health = 1e6 }))
        us.target = mob
        s, fired = nil, 0
    end)

    -- Fires the observer's stream up to world time `t` into the instance (at its own clock: world time + 100), then
    -- one display cycle and a fresh reset.
    local function upTo(t)
        s = s or observer.observe(W, setmetatable({ gcdSpell = 61304 }, { __index = observer.DEFAULTS }))
        local ctl = H.ctl
        while fired < s.n and s.t[fired + 1] <= t do
            fired = fired + 1
            local i = fired
            ctl.now = 100 + s.t[i]
            local ev = s.ev[i]
            if ev:byte(1) == 64 then
                -- the drive's answers are in the world's clock; the instance's runs 100 s on
                local a1, a2 = s.a1[i], s.a2[i]
                if ev == "@casting" or ev == "@channel" then
                    a1, a2 = a1 and a1 + 100000, a2 and a2 + 100000
                end
                drive.op({}, ctl, ev, a1, a2, s.a3[i], s.a4[i], s.a5[i])
            else
                H.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
            end
        end
        assert(headless.cycle(H, 100 + t))
        st.reset("Primary", true)
    end

    it("reads a channel as casting, its remains from UnitChannelInfo, and nothing after its stop", function()
        W.t = 1
        assert.is_true(
            W.press(us, "cannibalize", { spell = CANNIBALIZE, gcd = 1.5, channel = { length = 10, tick = 2 } })
        )
        W.run(20)
        upTo(4)
        assert.is_true(st.buff.casting.up)
        assert.is_true(st.channeling)
        assert.is_true(math.abs(st.channel_remains - 7) < 0.05, tostring(st.channel_remains))
        upTo(12)
        assert.is_false(st.buff.casting.up)
        assert.are.equal(0, st.channel_remains)
    end)

    it("reads a hard cast as casting from its UNIT_SPELLCAST_START, not as a channel", function()
        local slam = H.Hekili.Class.abilities.slam
        W.t = 1
        assert.is_true(W.press(us, "slam", { spell = slam.id, gcd = 1.5, cast = 1.5 }))
        W.run(5)
        upTo(1.8)
        assert.is_true(st.buff.casting.up)
        assert.is_false(st.channeling)
        assert.is_true(math.abs(st.buff.casting.remains - 0.7) < 0.05, tostring(st.buff.casting.remains))
        upTo(3)
        assert.is_false(st.buff.casting.up)
    end)
end)
