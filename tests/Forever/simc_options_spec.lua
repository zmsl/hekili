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

-- L1755 (owner: "c+hold"): a channel's interrupt_if is read where wowsims reads its interruptIf (dot.go periodicTick,
-- apl.go DoNextAction): at each tick but the last, with the GCD ready or more than the spell queue window from ready,
-- and at the GCD's end; once due it stays due until the channel ends.
describe("interrupt_if on a channel line: read at wowsims's points, held once due", function()
    -- Bloodrage above Cannibalize's line (10 s from world time 1, a tick each 2 s), its interrupt_if `cond(s)` (`s` s
    -- into the channel at the instant read); `gcd`: a GCD the instance sees from the channel's start. Returns at(t,
    -- over): the first recommendation's name and time at world time `t` (`over`: the GCD's entry cleared first).
    local function cutRig(cond, gcd)
        local H, W, us, upTo =
            rig({ line("bloodrage"), line("cannibalize", { interrupt_if = "1" }), line("battle_shout") })
        H.Hekili.Class.abilities.cannibalize.tick_time = 2
        local st = H.Hekili.State
        H.Hekili.Scripts.Channels[ww.PACK].cannibalize.interrupt_if = function()
            return cond(st.query_time - 101)
        end
        W.t = 1
        assert.is_true(
            W.press(us, "cannibalize", { spell = CANNIBALIZE, gcd = 1.5, channel = { length = 10, tick = 2 } })
        )
        W.run(20)
        if gcd then
            H.ctl.cooldown[H.ns.GCD_SPELL] = { isActive = true, isOnGCD = false, startTime = 101, duration = gcd }
        end
        return function(t, over)
            if over then
                H.ctl.cooldown[H.ns.GCD_SPELL] = nil
                gcd = nil
            end
            local out = upTo(t)
            st.reset("Primary", true)
            local left = math.max(0, 101 + (gcd or 0) - (100 + t))
            assert.is_true(math.abs(st.cooldown.global_cooldown.remains - left) < 1e-6, "the GCD the instance sees")
            return out.recs[1].actionName, out.recs[1].time
        end,
            H
    end

    it("a condition turned true mid-tick waits for the next tick", function()
        local on = false
        local at = cutRig(function()
            return on
        end)
        at(3) -- the first tick (2 s in), read false
        on = true
        local name, t = at(3.2)
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 1.8) < 0.05, tostring(t)) -- the second tick, 4 s in
    end)

    it("never in the last tick's interval (the ticks are done there)", function()
        local on = false
        local at = cutRig(function()
            return on
        end)
        at(9) -- the fourth tick, read false
        on = true
        local name, t = at(9.2)
        assert.is_true(name ~= "bloodrage" or t > 1.7, tostring(name) .. " at " .. tostring(t))
    end)

    it("once due, holds until the channel ends, the condition false again", function()
        local on = true
        local at = cutRig(function()
            return on
        end)
        local name, t = at(3) -- the first tick
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.05, tostring(t))
        on = false
        for _, w in ipairs({ 3.2, 3.4, 3.8, 4.6 }) do
            name, t = at(w)
            assert.are.equal("bloodrage", name)
            assert.is_true(t < 0.05, w .. ": " .. tostring(t))
        end
    end)

    -- an update late after a tick reads that tick as the last update forecast it there, not as of its own now (the
    -- reviewer's DoT falling between the tick and the update)
    it("a late update reads the passed tick as forecast at it", function()
        local at = cutRig(function(s)
            return s < 2.1 -- true at the first tick, false 0.3 s after it
        end)
        local name, t = at(2.9)
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 0.1) < 0.05, tostring(t))
        name, t = at(3.3)
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.05, tostring(t))
        at = cutRig(function(s)
            return s > 2.1 -- false at the first tick, true 0.3 s after it
        end)
        at(2.9)
        name, t = at(3.3)
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 1.7) < 0.05, tostring(t)) -- the second tick
    end)

    it("reads at the GCD's end inside the channel", function()
        local at = cutRig(function()
            return true
        end, 1.5)
        local name, t = at(1.2)
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 1.3) < 0.05, tostring(t)) -- the GCD's end, 1.5 s in, before the first tick
    end)

    it("holds past the GCD's end once the client reads the GCD as over (no start, no duration)", function()
        local at = cutRig(function()
            return true
        end, 1.5)
        local name, t = at(1.2)
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 1.3) < 0.05, tostring(t))
        for _, w in ipairs({ 2.6, 2.8, 3.4 }) do
            name, t = at(w, true) -- the GCD entry cleared: the live client's answer once it is over
            assert.are.equal("bloodrage", name)
            assert.is_true(t < 0.05, w .. ": " .. tostring(t))
        end
    end)

    -- review I-A: in dual mode Primary (capped at one target) and AOE (three at least) read a count-dependent condition
    -- (Affliction's Wrack Blood Fury clause reads active_enemies=1) each for itself: AOE's verdict never settles
    -- Primary's tick, so Primary's wait does not blink, and AOE never shows the cut its own condition rejects
    it("Primary and AOE keep their own verdicts in dual mode (a count-dependent condition)", function()
        local st
        local at, H = cutRig(function()
            return st.active_enemies == 1
        end)
        st = H.Hekili.State
        H.Hekili.Engine.settings.toggles.mode.value = "dual"
        assert.is_true(H.Hekili.Engine.Subscribe("AOE", function() end))
        local aoe = H.Hekili.Engine.Output.AOE
        local name, t = at(2.9) -- Primary forecasts the first tick (2 s in) due
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 0.1) < 0.05, tostring(t))
        for _, w in ipairs({ 3.3, 3.5, 4.9, 5.3 }) do
            name, t = at(w)
            assert.are.equal("bloodrage", name)
            assert.is_true(t < 0.05, w .. ": " .. tostring(t))
            local r = aoe.recs[1]
            assert.is_true(r.actionName ~= "bloodrage" or r.time > 0.05, w .. ": AOE " .. tostring(r.time))
        end
    end)

    -- review m1 (recast first against the hold): at a tick where the walk's pick is the channel's own line (Bloodrage on
    -- cooldown until 0.5 s after it, Cannibalize ready), wowsims recasts rather than cuts. No hold is set there, so
    -- Bloodrage off cooldown between ticks does not surface the cut: it waits for the next tick (4 s in)
    it("sets no hold at a tick whose pick is the channel itself (recast first)", function()
        local at, H = cutRig(function()
            return true
        end)
        at(2.5)
        local cd = H.ctl.cooldown
        cd[CANNIBALIZE] = nil
        cd[H.Hekili.Class.abilities.bloodrage.id] =
            { isActive = true, isOnGCD = false, startTime = 103.5 - 60, duration = 60 }
        for _, w in ipairs({ 3, 3.2, 3.6, 4.2 }) do
            local name, t = at(w)
            assert.is_true(
                name ~= "bloodrage" or math.abs(t - (5 - w)) < 0.05,
                w .. ": " .. tostring(name) .. " at " .. tostring(t)
            )
        end
        local name, t = at(5)
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.05, tostring(t))
        -- the same tick forecast from before it, then settled late from that forecast (Bloodrage off cooldown 0.6 s
        -- after it): the forecast's pick there is the channel, so the late update sets no hold either
        at, H = cutRig(function()
            return true
        end)
        at(2)
        cd = H.ctl.cooldown
        cd[CANNIBALIZE] = nil
        cd[H.Hekili.Class.abilities.bloodrage.id] =
            { isActive = true, isOnGCD = false, startTime = 103.6 - 60, duration = 60 }
        for _, w in ipairs({ 2.5, 3.4, 3.7 }) do
            name, t = at(w)
            assert.is_true(
                name ~= "bloodrage" or math.abs(t - (5 - w)) < 0.05,
                w .. ": " .. tostring(name) .. " at " .. tostring(t)
            )
        end
    end)

    -- a cut held from an earlier update survives a later walk that stops at the channel's own line (nothing above it
    -- passes there), now and at a forecast point, with no error; the hold shows again once the line above is back
    it("leaves a held cut to a later walk that stops at the channel's own line", function()
        local at, H = cutRig(function()
            return true
        end)
        H.Hekili.Class.abilities.cannibalize.tick = function() end -- a channel whose ticks act (Wrack's): walked at each
        at(2.5)
        local cd, bloodrage = H.ctl.cooldown, H.Hekili.Class.abilities.bloodrage.id
        cd[CANNIBALIZE] = nil
        local name, t = at(3) -- the first tick, Bloodrage ready: held
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.05, tostring(t))
        cd[bloodrage] = { isActive = true, isOnGCD = false, startTime = 103.2, duration = 60 }
        at(3.2)
        cd[bloodrage] = nil
        name, t = at(3.9) -- Bloodrage back off cooldown, between ticks: the hold still stands
        assert.are.equal("bloodrage", name)
        assert.is_true(t < 0.05, tostring(t))
    end)

    it("reads a tick with the GCD more than the spell queue window away, not one within it", function()
        local early = function(s)
            return s < 2.1 -- true at the first tick only
        end
        local name, t = cutRig(early, 2.6)(1.2) -- the GCD 0.6 s from ready at the first tick: due there
        assert.are.equal("bloodrage", name)
        assert.is_true(math.abs(t - 2.4) < 0.05, tostring(t)) -- shown at the GCD's end
        name, t = cutRig(early, 2.3)(1.2) -- 0.3 s from ready: not read there; false at the GCD's end
        assert.is_true(name ~= "bloodrage" or t > 3, tostring(name) .. " at " .. tostring(t))
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
