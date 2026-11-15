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
local DW = require("Forever.helpers.druid_loop_world")

-- A Warrior booted Undead (Cannibalize, Hekili_Shared's race pack, is the channel), Primary subscribed, the pack's
-- default list replaced by `list` (`lists`: more named lists beside it); a world whose observer stream feeds the
-- instance (as channel_engine_spec does).
local function rig(list, lists)
    local c = ww.character()
    c.race = "Scourge"
    c.known[#c.known + 1] = CANNIBALIZE
    local H = headless.new({ character = c, pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    lists = lists or {}
    lists.default = list
    H.Hekili.DB.profile.packs[ww.PACK].lists = lists
    H.Hekili:LoadScripts()
    H.Hekili:ReviewPacks() -- marks the new lists active (a called list is walked only then)
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
    -- `mods`: more options on the channel's line; `ticks`: give Cannibalize a 2 s tick_time, so its interrupt and
    -- interrupt_if checks (which need tick data) can run; `at`: the world time sampled (default 5, 4 s in: a tick)
    local function firstMidChannel(flag, noneAbove, mods, ticks, at)
        local chan = line("cannibalize", mods)
        chan.interrupt_global = flag
        local list = { line("bloodrage"), chan, line("battle_shout") }
        if noneAbove then
            table.remove(list, 1)
        end
        local H, W, us, upTo = rig(list)
        if ticks then
            H.Hekili.Class.abilities.cannibalize.tick_time = 2
        end
        W.t = 1
        assert.is_true(
            W.press(us, "cannibalize", { spell = CANNIBALIZE, gcd = 1.5, channel = { length = 10, tick = 2 } })
        )
        W.run(20)
        local out = upTo(at or 5)
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

    -- SimC: interrupt_global widens interrupt / interrupt_if to the whole priority (Hekili's already are), never
    -- overrides them; on its own, or beside interrupt=0, it breaks the channel itself. Values are strings, as the
    -- editor stores them.
    it("=1 with a false interrupt_if: the condition holds the channel", function()
        local name, t = firstMidChannel("1", false, { interrupt_if = "time<0" }, true)
        assert.is_true(t > 5, tostring(name) .. " at " .. tostring(t))
    end)

    it("=1 with a true interrupt_if: the channel breaks for the higher line", function()
        local name, t = firstMidChannel("1", false, { interrupt_if = "time>=0" }, true)
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.5, tostring(t))
    end)

    it("=1 with interrupt=1: interrupt decides, the channel breaks at its next tick", function()
        local name, t = firstMidChannel("1", false, { interrupt = "1" }, true) -- 4 s in: at a tick
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.1, tostring(t))
        name, t = firstMidChannel("1", false, { interrupt = "1" }, true, 4.5) -- 3.5 s in: mid-tick
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 0.5) < 0.1, tostring(t))
    end)

    it("=1 with interrupt=0: breaks as the flag alone", function()
        local name, t = firstMidChannel("1", false, { interrupt = "0" }, true)
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.5, tostring(t))
    end)
end)

describe("max_energy on a line", function()
    -- A Feral cat in combat with 5 combo points and `energy` (plain to the fake client), the list one Ferocious Bite
    -- line; returns the first recommendation's name and time.
    -- `secret`: the energy is read plain once out of combat, then secret in combat (Forever's case: the belief's
    -- estimate and floor carry it); `extra`: more lines after Bite's; mana is plain at 2674.
    local function bite(energy, flag, secret, extra)
        local c = DW.Feral.character()
        c.power = { type = 3, token = "ENERGY", max = 100, value = energy }
        local H = headless.new({ character = c, pack = DW.Feral.PACK })
        assert.are.same({}, H.loadErrors)
        local hk = H.Hekili
        local list = { line("ferocious_bite", { max_energy = flag }) }
        for _, e in ipairs(extra or {}) do
            list[#list + 1] = e
        end
        hk.DB.profile.packs[DW.Feral.PACK].lists = { default = list }
        hk:LoadScripts()
        H.ctl.power[0], H.ctl.power[3], H.ctl.power[4] = 2674, energy, 5
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(hk.Engine.Subscribe("Primary", function() end))
        if secret then
            assert(headless.cycle(H, H.ctl.now + 0.2))
            H.ctl.power[3] = nil -- secret from here
        end
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        assert(headless.cycle(H, H.ctl.now + (secret and 1 or 0.2)))
        assert.are.same({}, H.errors)
        local r = hk.Engine.Output.Primary.recs[1]
        return r.actionName, r.time, hk
    end

    it("=1 with secret energy at the cap: Bite now, not held short of it", function()
        local name, t, hk = bite(100, 1, true)
        assert.are.equal("ferocious_bite", name)
        assert.is_true(t < 0.5, tostring(t))
        assert.is_false(hk.State.nearCost, "ready, not near its cost")
    end)

    -- TimeToReady of `key` on line 2 (max_energy=1) and line 3 (no flag) at 60 energy: the flag changes nothing for an
    -- ability without excess_cap, nor for one paid in another resource
    for _, key in ipairs({ "rake", "faerie_fire" }) do
        it("=1 on " .. key .. " (no excess_cap): no change to its readiness", function()
            local _, _, hk = bite(60, nil, false, { line(key, { max_energy = 1 }), line(key) })
            local st = hk.State
            st.reset("Primary", true)
            st.scriptID = DW.Feral.PACK .. ":default:2"
            assert.is_true(st.args.max_energy == 1)
            local flagged = st:TimeToReady(key)
            st.scriptID = DW.Feral.PACK .. ":default:3"
            assert.are.equal(st:TimeToReady(key), flagged)
            assert.is_true(flagged < 3600, tostring(flagged))
        end)
    end

    it("the pack declares Bite's excess cap: all the energy it holds (wowsims ferocious_bite.go)", function()
        local _, _, hk = bite(100)
        assert.is_not_nil(hk.Class.abilities.ferocious_bite.excess_cap)
    end)

    it("=1: waits for full energy (the cost plus every point Bite converts)", function()
        local name, t = bite(60, 1)
        assert.are.equal("ferocious_bite", name)
        assert.is_true(t > 2, tostring(t))
        name, t = bite(100, 1)
        assert.are.equal("ferocious_bite", name)
        assert.is_true(t < 0.5, tostring(t))
    end)

    it("the editor shows Max Energy where the line's ability declares excess_cap, not by name", function()
        local _, _, hk = bite(100)
        hk:EmbedPackOptions()
        -- the max_energy toggle under the Feral pack's group in the options tree
        local function find(t, inPack, seen)
            if type(t) ~= "table" or seen[t] then
                return nil
            end
            seen[t] = true
            for k, v in pairs(t) do
                if k == "max_energy" and inPack and type(v) == "table" and v.type == "toggle" then
                    return v
                end
                local hit = find(v, inPack or k == DW.Feral.PACK, seen)
                if hit then
                    return hit
                end
            end
        end
        local toggle = assert(find(hk.Options, false, {}), "no max_energy toggle under the Feral pack")
        local list = hk.DB.profile.packs[DW.Feral.PACK].lists.default
        assert.is_false(toggle.hidden())
        list[1].action = "rake"
        assert.is_true(toggle.hidden())
        list[1].action = "ferocious_bite" -- the same name without the field: hidden
        hk.Class.abilities.ferocious_bite.funcs.excess_cap = nil
        assert.is_true(toggle.hidden())
    end)

    it("absent and =0: Bite at its cost", function()
        for _, flag in ipairs({ false, 0 }) do
            local name, t = bite(60, flag or nil)
            assert.are.equal("ferocious_bite", name)
            assert.is_true(t < 0.5, tostring(flag) .. ": " .. tostring(t))
        end
    end)
end)

describe("use_while_casting on a line", function()
    -- Bloodrage (off the GCD by use_off_gcd=1) above the spell being cast; 0.5 s into Slam's 1.5 s cast, or 4 s into
    -- Cannibalize's 10 s channel, Primary's first recommendation.
    local function firstMidCast(kind, flag)
        local H, W, us, upTo = rig({
            line("bloodrage", { use_off_gcd = 1, use_while_casting = flag }),
            line("battle_shout"),
        })
        W.t = 1
        if kind == "cast" then
            local slam = H.Hekili.Class.abilities.slam
            assert.is_true(W.press(us, "slam", { spell = slam.id, gcd = 1.5, cast = 1.5 }))
        else
            assert.is_true(
                W.press(us, "cannibalize", { spell = CANNIBALIZE, gcd = 1.5, channel = { length = 10, tick = 2 } })
            )
        end
        W.run(20)
        local out = upTo(kind == "cast" and 1.5 or 5)
        local name, t = out.recs[1].actionName, out.recs[1].time
        local r2 = out.recs[2]
        H.Hekili.State.reset("Primary", true)
        assert.is_true(H.Hekili.State.buff.casting.up, "still casting at the update")
        return name, t, r2
    end

    for _, kind in ipairs({ "cast", "channel" }) do
        it("=1: recommended during a " .. kind .. "; the next line still waits for its end", function()
            local name, t, r2 = firstMidCast(kind, 1)
            assert.are.equal("bloodrage", name)
            assert.is_true(t < 0.3, tostring(t))
            assert.are.equal("battle_shout", r2.actionName)
            assert.is_true(r2.time > (kind == "cast" and 0.9 or 5.5), tostring(r2.time))
        end)

        it("absent and =0: waits for the " .. kind .. " to end", function()
            for _, flag in ipairs({ false, 0 }) do
                local name, t = firstMidCast(kind, flag or nil)
                assert.is_true(t > 0.5, tostring(flag) .. ": " .. tostring(name) .. " at " .. tostring(t))
            end
        end)
    end

    -- SimC means the flag for instants used mid-cast: a flagged ability with its own cast time still waits the
    -- player's cast out (it would end it)
    it("=1 on an ability with a cast time: still waits for the channel to end", function()
        local H, W, us, upTo =
            rig({ line("slam", { use_while_casting = 1 }), line("bloodrage", { use_while_casting = 1 }) })
        H.Hekili.Class.abilities.slam.spend = 0 -- rage is secret here: free Slam, so only the channel can hold it
        W.t = 1
        assert.is_true(
            W.press(us, "cannibalize", { spell = CANNIBALIZE, gcd = 1.5, channel = { length = 10, tick = 2 } })
        )
        W.run(20)
        upTo(5)
        local st = H.Hekili.State
        st.reset("Primary", true)
        assert.is_true(st.channeling)
        st.scriptID = ww.PACK .. ":default:2"
        assert.is_true(st:TimeToReady("bloodrage") < 0.3, "the flagged instant goes now")
        st.scriptID = ww.PACK .. ":default:1"
        local t = st:TimeToReady("slam")
        assert.is_true(t > st.channel_remains - 0.1, tostring(t) .. " vs " .. tostring(st.channel_remains))
    end)

    -- the cast-stop site in the recommendation loop: a flagged ability with a cast time, recommended as the channel
    -- breaks (interrupt_global), still ends the channel, so the next recommendation follows its cast, not the old
    -- channel's end
    it("=1 on an ability with a cast time: casting it still ends the channel", function()
        local function next(flag)
            local H, W, us, upTo = rig({
                line("slam", { use_while_casting = flag }),
                line("cannibalize", { interrupt_global = "1" }),
                line("battle_shout"),
            })
            H.Hekili.Class.abilities.slam.spend = 0 -- rage is secret here: free Slam
            W.t = 1
            assert.is_true(
                W.press(us, "cannibalize", { spell = CANNIBALIZE, gcd = 1.5, channel = { length = 10, tick = 2 } })
            )
            W.run(20)
            local recs = upTo(4.5).recs
            assert.are.equal("slam", recs[1].actionName)
            assert.is_true(recs[1].time < 0.3, tostring(recs[1].time))
            return recs[2].actionName, recs[2].time
        end
        local name, t = next(nil)
        assert.are.equal("cannibalize", name)
        assert.is_true(t < 2, "unflagged: " .. tostring(t))
        assert.are.same({ name, t }, { next("1") })
    end)

    -- an option on a line inside a called list is that line's own (args per entry)
    it("=1 on a line inside a called list: recommended during the cast", function()
        local H, W, us, upTo = rig({ line("call_action_list", { list_name = "sub" }), line("battle_shout") }, {
            sub = { line("bloodrage", { use_off_gcd = "1", use_while_casting = "1" }) },
        })
        W.t = 1
        local slam = H.Hekili.Class.abilities.slam
        assert.is_true(W.press(us, "slam", { spell = slam.id, gcd = 1.5, cast = 1.5 }))
        W.run(20)
        local recs = upTo(1.5).recs
        assert.are.equal("bloodrage", recs[1].actionName)
        assert.is_true(recs[1].time < 0.3, tostring(recs[1].time))
        assert.are.equal("battle_shout", recs[2].actionName)
        assert.is_true(recs[2].time > 0.9, tostring(recs[2].time))
    end)
end)

describe("the three options through the importer", function()
    it("survive a SimC import, the compiled line and a priority share string", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local hk = H.Hekili
        local list = hk:ParseActionList(
            "actions+=/ferocious_bite,max_energy=1\n"
                .. "actions+=/bloodrage,use_while_casting=1\n"
                .. "actions+=/cannibalize,interrupt_global=1\n"
        )
        assert.are.same({ 1, 1, 1 }, { list[1].max_energy, list[2].use_while_casting, list[3].interrupt_global })

        hk.DB.profile.packs[ww.PACK].lists = { default = list }
        hk:LoadScripts()
        local DB = hk.Scripts.DB
        for i, k in ipairs({ "max_energy", "use_while_casting", "interrupt_global" }) do
            local mod = DB[ww.PACK .. ":default:" .. i].Modifiers[k]
            assert.is_function(mod, k)
            assert.are.equal(1, mod(), k)
        end

        local e = hk.DeserializeActionPack(hk.SerializeActionPack(ww.PACK)).payload.lists.default
        assert.are.same({ 1, 1, 1 }, { e[1].max_energy, e[2].use_while_casting, e[3].interrupt_global })
        assert.are.same({}, H.errors)
    end)
end)
