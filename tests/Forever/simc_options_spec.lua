-- tests/Forever/simc_options_spec.lua (lane simc-options-085, L975): three SimC action options the editor and importer
-- accept, read by the engine: interrupt_global (a channel line's flag: any line above it in the whole priority may break
-- the channel), max_energy (an entry waits for the cost plus the ability's declared excess cap) and use_while_casting
-- (an entry need not wait for the player's cast to end). Each flag reads as absent, =0 and =1.
local headless = require("Game.harness.headless")
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local observer = require("Game.harness.observer")
local drive = require("Game.harness.drive")
local ww = require("Forever.helpers.warrior_world")

local CANNIBALIZE = 20577

-- A Warrior booted Undead (Cannibalize, Hekili_Shared's race pack, is the channel), Primary subscribed, the pack's
-- default list replaced by `list`; a world whose observer stream feeds the instance (as channel_engine_spec does).
local function rig(list)
    local c = ww.character()
    c.race = "Scourge"
    c.known[#c.known + 1] = CANNIBALIZE
    local H = headless.new({ character = c, pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    H.Hekili.DB.profile.packs[ww.PACK].lists = { default = list }
    H.Hekili:LoadScripts()
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    local W = world.new(1)
    local us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
    local mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 1, 1, 2 } }, health = 1e6 }))
    us.target = mob
    local s, fired = nil, 0
    -- fires the observer's stream up to world time `t` (the instance's clock runs 100 s on), then one display cycle
    local function upTo(t)
        s = s or observer.observe(W, setmetatable({ gcdSpell = 61304 }, { __index = observer.DEFAULTS }))
        local ctl = H.ctl
        while fired < s.n and s.t[fired + 1] <= t do
            fired = fired + 1
            local i = fired
            ctl.now = 100 + s.t[i]
            local ev = s.ev[i]
            if ev:byte(1) == 64 then
                local a1, a2 = s.a1[i], s.a2[i]
                if ev == "@casting" or ev == "@channel" then
                    a1, a2 = a1 and a1 + 100000, a2 and a2 + 100000
                end
                drive.op({}, ctl, ev, a1, a2, s.a3[i], s.a4[i], s.a5[i])
                if ctl.channel then
                    ctl.channel.spell = CANNIBALIZE -- the drive's channel bar names no spell; the engine needs it
                end
            else
                H.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
            end
        end
        assert(headless.cycle(H, 100 + t))
        assert.are.same({}, H.errors)
        return H.Hekili.Engine.Output.Primary
    end
    return H, W, us, upTo
end

local function line(action, extra)
    local e = { enabled = true, action = action }
    for k, v in pairs(extra or {}) do
        e[k] = v
    end
    return e
end

describe("interrupt_global on a channel line", function()
    -- Bloodrage above the channel's line, Battle Shout below it; mid-channel (4 s into Cannibalize's 10 s) the
    -- first recommendation is Bloodrage now only when the channel's line carries interrupt_global=1.
    local function firstMidChannel(flag, noneAbove)
        local list = {
            line("bloodrage"),
            line("cannibalize", { interrupt_global = flag }),
            line("battle_shout"),
        }
        if noneAbove then
            table.remove(list, 1)
        end
        local H, W, us, upTo = rig(list)
        W.t = 1
        assert.is_true(
            W.press(us, "cannibalize", { spell = CANNIBALIZE, gcd = 1.5, channel = { length = 10, tick = 2 } })
        )
        W.run(20)
        local out = upTo(5)
        local name, t = out.recs[1].actionName, out.recs[1].time
        H.Hekili.State.reset("Primary", true)
        assert.is_true(H.Hekili.State.channeling, "still channeling at the update")
        return name, t
    end

    it("=1: a higher line breaks the channel now", function()
        local name, t = firstMidChannel(1)
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.5, tostring(t))
    end)

    it("=1: a line below the channel's never breaks it (the walk stops at the channel's line)", function()
        local name, t = firstMidChannel(1, true)
        assert.is_false(name == "battle_shout" and t < 5, tostring(name) .. " at " .. tostring(t))
    end)

    it("absent: nothing breaks the channel before it ends", function()
        local name, t = firstMidChannel(nil)
        assert.is_true(t > 5, tostring(name) .. " at " .. tostring(t))
    end)

    it("=0: nothing breaks the channel before it ends", function()
        local name, t = firstMidChannel(0)
        assert.is_true(t > 5, tostring(name) .. " at " .. tostring(t))
    end)
end)
