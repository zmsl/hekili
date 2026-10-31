-- tests/Game/harness/loop.lua (headless loop design §2, §4): stock Hekili pressing its own first icon against the
-- harness's world. Two instances in lockstep on one world (§2.2): ours, reading the Forever client the observer
-- encodes, and the oracle, reading a secret-free client (k.plain, design §4/D4) with the target's health rows raw.
-- Run A: ours drives, the oracle shadows; run B: the same seed, a fresh world, the oracle drives (§2.3).
-- Class-neutral (the boundary rule): the content passes the character, the pack, the press resolution, the usability
-- answers, the true power gain per hit (content.gain, for the content's power type), the world's knobs and the debuff
-- list.
local ab = require("Game.harness.ab")
local headless = require("Game.harness.headless")
local observer = require("Game.harness.observer")
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")
local flicker = require("Game.harness.flicker")
local timing = require("Game.harness.timing")

local M = {}

-- The CPU calibration (pack_gate.CPU_RATIO): a fixed pure-Lua workload, hash reads through a metatable chain over a
-- preallocated working set (the engine's state reads, in miniature), timed once per counted run in the same process,
-- so load that slows the engine through shared cores and cache slows it too. About 7 ms here alone; allocates nothing.
local CAL_N, CAL_ROUNDS = 4096, 30
local calSet = {}
do
    local meta = { __index = { x = 1, y = 2 } }
    for i = 1, CAL_N do
        calSet[i] = setmetatable({ a = i, b = 2 * i }, meta)
    end
end

--- The calibration workload's process CPU time, in ms (and its checksum, so no step is dead code).
function M.calibrate()
    local c0, sum = os.clock(), 0
    for _ = 1, CAL_ROUNDS do
        for i = 1, CAL_N do
            local t = calSet[i]
            sum = sum + t.a + t.x + t.y - t.b
        end
    end
    return (os.clock() - c0) * 1000, sum
end

-- Bytes per Update (reported, never gated): every this many counted ticks, one cycle with the collector stopped. A
-- running collector's sweep inside a cycle makes the delta negative; stopping it on every tick would keep the timed
-- cycles from doing any collection at all.
M.BYTES_EVERY = 8

M.TICK = 0.2 -- 5 Hz, the in-game combat rate (D1); o.hz = 10 the option
M.REACT = 0.05 -- a first icon whose wait is at most this is shown as ready: pressed

--- Ready while short (the owner's rule, dim never promote): an icon pressed as ready with the truth before the press
--- under its cost and nothing in flight whose spend explains it. The frames read after the press, so they can't see it.
function M.readyShort(pre, p, us, t)
    return (p.cost or 0) > pre and (us.castUntil or 0) <= t and us.gcdUntil <= t + 1e-9
end
M.PULL = 3 -- the world starts this long before the pull, the target selected (precombat presses)
M.GAP = 30 -- out of combat between two fights on one boot (consecutive pulls)
-- The display-side hold experiment (flicker.hold) on our instance's shown queue: o.hold, else this switch (off)
M.HOLD = os.getenv("HEKILI_LOOP_HOLD") == "1"
-- The shipped steady icons (Engine/Output.lua, the spec's experimental steadyIcons) on our instance: o.steady, else
-- this switch (off; the flicker design study's hold3). o.steady is true (hold 1) or the updates to hold (1 to 3);
-- HEKILI_LOOP_STEADY=N sets the switch to N.
M.STEADY = tonumber(os.getenv("HEKILI_LOOP_STEADY")) -- 0 is off
    or os.getenv("HEKILI_LOOP_HOLD") == "3"
-- The oracle's facade rows answered by the client (§4's override): the target's health, and the debuff row Hekili's
-- aura scan reads (raw since VirtualState counted a modelled stack on top of a plain read that arrived before the
-- cast's drain, fixed in Auras.lua's I.AuraModel and pinned in loop_warrior_spec). The buff row stays VirtualState's: our
-- forms become buffs in the belief, and the client's list does not hold them.
M.RAW = { "UnitHealth", "UnitHealthMax", "C_UnitAuras.GetDebuffDataByIndex" }

--- Boots the two instances for `content` (one boot per busted block, §1.3): { content, us, oracle }. `content`:
--- character(), PACK, resolve(key, H), usable(H), gain(pt, hand, amount, flag) (what a landed wound of ours pays in
--- power type `pt`, the character's), WORLD (scenario knobs), uptime(H); optional OBSERVE (observer knobs over the
--- loop's: another power's reads, the forms), SCENARIO (headless.new's `scenario`; default "sim": the settings'
--- harness defaults, wowsims's scenario; "game" boots both instances with the in-game ones).
function M.new(content)
    local L = { content = content }
    local character = content.character()
    L.form, L.power = character.form, character.power
    local pt = L.power.type
    L.gain = function(hand, amount, flag) -- the swing-paid power is the character's (scenarios.world's `pt`)
        return content.gain(pt, hand, amount, flag)
    end
    local scenario = content.SCENARIO or "sim"
    scenario = scenario ~= "game" and scenario or nil
    L.us = headless.new({ character = character, pack = content.PACK, scenario = scenario })
    L.oracle = headless.new({ character = character, pack = content.PACK, raw = M.RAW, scenario = scenario })
    for _, H in ipairs({ L.us, L.oracle }) do
        H.ctl.inRange.target = true -- a world without positions (no W.distance): every target in range
    end
    L.answers = content.usable(L.oracle)
    L.uptime = content.uptime(L.oracle)
    return L
end

-- Fires the client events `obs` releases up to world time `t` into instance `H`, each at its own time (base + t);
-- a cooldown's start, an aura's expiry, a totem's start and our cast bar (ms) move to the instance's clock.
local function feed(H, obs, t, base, sink)
    local s = obs.s
    local first, last = obs.step(t)
    local ctl = H.ctl
    for i = first, last do
        ctl.now = base + s.t[i]
        local ev = s.ev[i]
        if ev:byte(1) == 64 then -- "@"
            local a1, a2, a3, a4 = s.a1[i], s.a2[i], s.a3[i], s.a4[i]
            if (ev == "@casting" or ev == "@channel") and a1 then -- gap BD: the bar was on the world's clock
                a1, a2 = a1 + base * 1000, a2 + base * 1000
            elseif ev == "@cooldown" and type(a2) == "number" and a2 > 0 then
                a2 = base + a2
            elseif ev == "@aura" and a4 > 0 then
                a4 = base + a4
            elseif ev == "@totem" and type(a3) == "number" and a3 > 0 then
                a3 = base + a3
            end
            drive.op(sink, ctl, ev, a1, a2, a3, a4, s.a5[i])
        else
            H.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
        end
    end
end

-- The first `n` entries of an instance's Primary queue into `q` (names, waits, costs in power `res`, else 0) and its
-- focus entry into slot flicker.FOCUS (the display's focus: the best tier within the Timeline's 10 s horizon, then the
-- soonest); returns how many.
local function queue(H, q, n, res)
    local out = H.Hekili.Engine.Output.Primary
    local k = math.min(n, out.count)
    for i = 1, k do
        local r = out.recs[i]
        q.name[i], q.time[i], q.cost[i] = r.actionName, r.time or 0, r.resource_type == res and r.cost or 0
    end
    for i = k + 1, n do
        q.name[i], q.time[i], q.cost[i] = false, 0, 0
    end
    local F = flicker.FOCUS
    q.name[F], q.time[F], q.cost[F] = false, 0, 0
    local best -- the display's rule (Timeline.lua FOCUS_BEST_TIER): the best tier, then the soonest; focus=0 is no tier
    for i = 1, out.count do
        local r = out.recs[i]
        if type(r.focus) == "number" and r.focus >= 1 and (best == nil or r.focus < best) and (r.time or 0) <= 10 then
            q.name[F], q.time[F], q.cost[F] = r.actionName, r.time or 0, r.resource_type == res and r.cost or 0
            best = r.focus
            if best == 1 then
                break
            end
        end
    end
    return k
end

-- Our events in the world's truth from index `from` into `e` (flicker.EVENTS flags, OR-ed in); the next index.
local function events(W, us, from, e)
    local truth = W.truth
    for i = from, #truth do
        local ev = truth[i]
        local k = ev.kind
        if ev.src == us then
            -- a hard cast's start and a channel's end are ours too (fix 22: the client sees them at the press)
            e.cast = e.cast
                or k == "cast"
                or k == "castStart"
                or k == "castStop"
                or k == "channelStop"
                or k == "strike"
                or k == "queue"
                or k == "unqueue"
            e.spend = e.spend or ((k == "cast" or k == "strike" or k == "gain") and (ev.cost or 0) > 0)
            e.avoid = e.avoid or (ev.act ~= nil and ev.act ~= "WOUND" and k ~= "tick")
            e.swing = e.swing or k == "swing"
            e.aura = e.aura or k == "cdreset"
        end
        e.aura = e.aura or k == "form" or (k == "aura" and (ev.dst == us or (us.target ~= nil and ev.dst == us.target)))
    end
    return #truth + 1
end

-- The believed cooldown remaining of ability `x` of instance `H` into `cd` (false: untracked), once a tick.
local function cooldown(cd, H, x, now)
    if x and cd[x] == nil then
        local a = H.Hekili.Class.abilities[x]
        local rec = a and type(a.id) == "number" and a.id > 0 and H.ns.VirtualState.Cooldown(a.id, now)
        cd[x] = rec and math.max(0, rec.est - now) or false
    end
end

--- Whether a refusal of `key` is the driver's own (§5.2 as built, the round-3 ruling): not when the shadow's queue `q`
--- (the oracle's, the same tick) showed the same first icon ready (wait at most `react`), a press it would have made
--- too: the harness's press protocol meeting the world's rage timing, not a belief error. No shadow (run B, a replay):
--- every refusal is the driver's.
function M.unmatched(key, q, react)
    return not (q and q.name[1] == key and q.time[1] <= react)
end

--- What pool `pt` of `e` at `v` (cap `max`) reaches over the out-of-combat gap between two fights (M.GAP): its idle
--- regen (the world's rate, the five-second rule open), else the world's out-of-combat `decay` ({ pt, rate, interval }:
--- stepped, the first quantum at combat's end: already taken when the world's own stop came, else now), else nil (the
--- content's start: combo points go with their target).
function M.rest(W, e, pt, v, decay, max)
    local rate = W.regenRate(e, pt, "idle")
    if rate > 0 then
        return math.min(max, v + rate * M.GAP)
    elseif decay and decay.pt == pt then
        local q = math.floor(M.GAP / decay.interval) + (W.combat and 1 or 0)
        return math.max(0, v - q * decay.rate * decay.interval)
    end
    return nil
end

-- The first on-GCD name of an instance's Primary queue (false: none): the replay's decision-point pick.
local function firstGcd(H)
    local out, abilities = H.Hekili.Engine.Output.Primary, H.Hekili.Class.abilities
    for i = 1, out.count do
        local a = abilities[out.recs[i].actionName]
        if a and a.gcd ~= "off" then
            return out.recs[i].actionName
        end
    end
    return false
end

--- One run of fight `seed`: the instances in `drivers` (each { H, plain }) stepped on one world in lockstep, the
--- first one's first icon pressed, each press resolved from the run's truth instance (the oracle when it is driven,
--- else the first driver). `o`: duration (combat seconds [180]), mobHealth, hz [5], react [REACT], reaction
--- (seconds an icon shows ready before the press [0]), others (archetypes on our target), trace (the facade's trace
--- each tick), on(run, steps, t) (a per-tick hook). Returns the run { W, us, ticks, presses, refused (by reason),
--- attempts, episodes, errors, raises, misses (unexpected run names), secrets (Facade.secrets), selfCheck (ticks where
--- the oracle's belief missed the truth, by field), combat, full, idle, up (by debuff key: in-combat ticks), ours and
--- theirs (first icons by in-combat tick), pressed and shadowPress (the driver's press, the shadow's would-be press, by
--- in-combat tick: loop.flips), focus (in-combat ticks whose first record of ours has `focus` set), gap (believed minus true power where they differ), cpu (ms per tick of
--- the first instance, timed around headless.cycle: VirtualState's flush and the timers as well as Update, so it errs
--- high; empty in a traced run, whose debug pass is not runtime cost), cal (M.calibrate's ms, timed once before an
--- untraced run's first tick), bytes and sampled (allocated over `sampled` cycles, every M.BYTES_EVERY-th cpu
--- tick, the collector stopped for each), damage, t }. `o.replay` (replay.lua's R: its world, no presses, wowsims's next cast as `theirs`, a cycle just before each
--- decision; `run.dec` { ours, theirs }: our first on-GCD icon and wowsims's on-GCD cast).
function M.run(L, seed, o, drivers)
    o = o or {}
    local content = L.content
    local tick = 1 / (o.hz or 5)
    local wo = setmetatable({
        pull = M.PULL,
        prepull = 0.1,
        duration = o.duration or 180,
        mobHealth = o.mobHealth or content.WORLD.mobHealth,
        pt = L.power.type,
        rage = L.gain,
        form = L.form,
        tag = "-" .. seed .. "-" .. #drivers, -- a fresh mob per run
        others = o.others, -- other sources on our target (scenarios.ARCHETYPES: the party report)
    }, { __index = content.WORLD })
    local R = o.replay -- a wowsims log's world (replay.lua): no presses, its casts as `theirs`
    if R then
        wo.pull, wo.duration, wo.targetLevel = R.pull, R.duration, R.targetLevel or wo.targetLevel
    end
    -- the pools the driver's last fight left, through the gap (M.rest): a fresh world of one boot starts there, as the
    -- belief does (a fight that ended dry starts dry, not full)
    local carry = not R and L.carry and L.carry[drivers[1].H]
    if carry then
        wo.power = carry.power or wo.power
        local res = {}
        for pt, r in pairs(content.WORLD.res or {}) do
            res[pt] = { cur = carry.res[pt] or r.cur, max = r.max }
        end
        wo.res = res
    end
    local W = R and R.world(wo, seed) or scenarios.world(wo, seed)
    local us = W.ents[1]
    local run = {
        W = W,
        us = us,
        ticks = 0,
        presses = 0,
        refused = {},
        unmatched = {},
        raises = 0,
        selfCheck = {},
        readyShort = 0,
    }
    -- the instance whose state is the run's truth, a press resolving from it: the oracle when it is driven, else the
    -- driver (a run of ours alone, ws.live, never steps the oracle, whose state then stays at its boot)
    local truth = drivers[1].H
    for _, d in ipairs(drivers) do
        truth = d.H == L.oracle and d.H or truth
    end
    -- the metrics' per-tick record (§5.1): in-combat ticks only, both queues' first icons, the truth
    run.combat, run.full, run.idle, run.attempts, run.episodes, run.up = 0, 0, 0, 0, 0, {}
    run.ours, run.theirs, run.gap, run.cpu, run.secrets, run.focus = {}, {}, {}, {}, {}, 0
    run.pressed, run.shadowPress = {}, {}
    run.dec = R and { ours = {}, theirs = {}, flips = 0 } or nil
    -- the flicker ledger's frames (flicker.frame), one an instance, over the run's events between two polls: run A
    -- and a replay only (run B, the oracle driving alone, is never read)
    local ledger = R ~= nil or #drivers > 1
    run.ev, run.frames = flicker.events(), {}
    for i = 1, ledger and #drivers or 0 do
        run.frames[i] = flicker.frame(run.ev)
    end
    local hold = o.hold
    if hold == nil then
        hold = M.HOLD
    end
    local steady = o.steady
    if steady == nil then
        steady = M.STEADY
    end
    if steady == 0 then
        steady = false -- 0 updates to hold is off
    end
    local res = L.power.token and L.power.token:lower()
    local pollEv, tickEv, nextEv = {}, {}, 1
    local steps = {}
    local arm = ab.ARMS[ab.arm()]
    for i, d in ipairs(drivers) do
        local id = d.H.Hekili.State.spec.id
        local sp = id and d.H.Hekili.DB.profile.specs[id]
        if sp then
            sp.steadyIcons = steady and not d.plain -- the oracle shadow never holds
            sp.steadyHold = type(steady) == "number" and steady or 1
        end
        -- the A/B arm's experimental toggles (providers decision 82), applied out of combat as the option does
        local perf = d.H.Hekili.DB.profile.performance
        perf.damageMeter, perf.cooldownViewer = arm.outcomes == "meter", arm.viewer
        d.H.Hekili:ProvidersChanged()
        local ctl = d.H.ctl -- a fresh world: the client's answers about it start fresh too
        ctl.combat, ctl.form, ctl.stealthed = false, L.form, false
        local fresh = {
            ctl.dead,
            ctl.current,
            ctl.cooldown,
            ctl.usable,
            ctl.unitHealth,
            ctl.unitHealthMax,
            ctl.totems,
            ctl.distance,
        }
        for _, t in ipairs(fresh) do
            for key in pairs(t) do
                t[key] = nil
            end
        end
        for _, list in pairs(ctl.auras) do
            list.HELPFUL, list.HARMFUL = {}, {}
        end
        ctl.auraError.target = nil
        -- UnitLevel is plain in combat on Forever (the facade's passthrough row); fake_api answers an unset unit secret
        -- `targetLevel` the content's answer for the target (-1: a boss, as Hekili's `boss` reads it)
        ctl.level.target, ctl.level.nameplate1 = wo.targetLevel or wo.level, wo.targetLevel or wo.level
        ctl.creature.target = us.target and us.target.creatureType -- the world's mob (nil: the fake's default)
        local k = setmetatable({
            usable = L.answers,
            gcdSpell = d.H.ns.VirtualStateInternal.GCD_SPELL,
            powerType = L.power.type, -- the content's power, not the observer's default
            powerToken = L.power.token,
        }, {
            __index = observer.DEFAULTS,
        })
        k.meter, k.viewer = arm.outcomes == "meter", arm.viewer -- the arm's shapes (none in the default arm)
        ab.observe(k) -- and its other knobs (the meter arm's taken lead, as the gates' streams)
        for key, v in pairs(content.OBSERVE or {}) do -- the content's client knobs (other powers' reads, forms)
            k[key] = v
        end
        if o.replay then
            k.powerMax = true -- the log's pools (replay.lua's maxOf), not the character sheet's
        end
        if d.plain then
            k.plain, k.usableDelay = true, 0
        end
        local base = d.H.ctl.now + M.GAP -- this instance's clock continues from its last fight
        -- the fresh world holds none of our buffs, cooldowns or totems and starts in the content's form: the client says
        -- so (plain reads out of combat, at the new fight's clock: a GCD flag's fall read at the old one would teach
        -- its length), or the instance keeps believing the last fight's (a self-buff or a long cooldown of run A
        -- carried into run B, a different world)
        ctl.now = base
        if d.plain then -- two world lines (run A's, run B's): its last read is the other world's, its gain to this one's
            -- first read no regen, yet a measurement over the 30 s gap (the Protection oracle's 18.12 for a world's 17.38)
            local res = d.H.ns.VirtualStateInternal.res
            for r = 1, res.n do
                res.pinValid[r] = false
            end
        end
        d.H.Fire("UNIT_AURA", "player")
        d.H.Fire("SPELL_UPDATE_COOLDOWN")
        d.H.Fire("UPDATE_SHAPESHIFT_FORM")
        for slot = 1, 4 do
            d.H.Fire("PLAYER_TOTEM_UPDATE", slot)
        end
        steps[i] = {
            H = d.H,
            obs = observer.new(W, k),
            base = base,
            sink = {}, -- drive.op's reused records (the cast bar): one an instance, each on its own clock (gap BD)
            q = { name = {}, time = {}, cost = {} },
            plain = d.plain,
            hold = (hold and not d.plain) and flicker.newHold() or nil,
        }
    end
    local errors0 = {}
    for i, st in ipairs(steps) do
        errors0[i] = #st.H.errors
    end
    local stopAt = W.stopAt
    local t = 0
    local lastRefused, readySince = false, {}
    local traced = {}
    run.cal = not o.trace and M.calibrate() or nil
    run.bytes, run.sampled = 0, 0
    if o.trace then -- the facade's trace (§5.1): Hekili's own debug pass, its lines counted and dropped
        for i, st in ipairs(steps) do
            local hk = st.H.Hekili
            traced[i] = { hk.Debug, hk.SaveDebugSnapshot }
            hk.Debug = function() end
            hk.SaveDebugSnapshot = function()
                return false
            end
        end
    end
    local function step(tc) -- the world to `tc`, every instance fed and cycled
        W.run(tc)
        if ledger or hold then -- the events the ledger and the hold read
            for _, key in ipairs(flicker.EVENTS) do
                pollEv[key] = false
            end
            nextEv = events(W, us, nextEv, pollEv)
            for _, key in ipairs(flicker.EVENTS) do
                tickEv[key] = tickEv[key] or pollEv[key]
            end
        end
        for i, st in ipairs(steps) do
            feed(st.H, st.obs, tc, st.base, st.sink)
            st.H.Hekili.ActiveDebug = o.trace or false
            local counted = i == 1 and not o.trace -- the traced fight's debug pass is not runtime cost
            -- the seed turns the phase: a fight's first cycle, the most expensive, must not be every fight's first sample
            local sampled = counted and (#run.cpu + seed) % M.BYTES_EVERY == 0
            local b0
            if sampled then -- a sweep inside the cycle would swamp the delta
                collectgarbage("stop")
                b0 = collectgarbage("count")
            end
            local c0 = os.clock()
            local ok = headless.cycle(st.H, st.base + tc)
            if counted then
                run.cpu[#run.cpu + 1] = (os.clock() - c0) * 1000
            end
            if sampled then
                run.bytes, run.sampled = run.bytes + (collectgarbage("count") - b0) * 1024, run.sampled + 1
                collectgarbage("restart")
            end
            st.H.Hekili.ActiveDebug = false
            if not ok then
                run.raises = run.raises + 1
            end
            queue(st.H, st.q, 3, res)
            if st.hold then
                flicker.hold(st.hold, st.q, o.react or M.REACT, pollEv.cast)
            end
        end
        if R and R.timing then -- the ready-time recorder (timing.lua): our queue and power band at this poll
            timing.poll(R.timing, tc, steps[1].H, W)
        end
    end
    local di = 1
    local lastGcd, tickPolled = nil, false -- the replay's first on-GCD icon at the last poll, and that poll a tick's
    while t < stopAt and not W.killAt do
        -- wowsims's decisions before this tick (replay): a cycle just before each cast; the on-GCD ones scored
        -- against our first on-GCD icon (an off-GCD cast would agree with whatever shows during a GCD)
        while R and R.decisions[di] and R.decisions[di].t < t + tick do
            local d = R.decisions[di]
            di = di + 1
            if d.t > t then
                step(d.t)
                if d.gcd then
                    local n = #run.dec.ours + 1
                    run.dec.ours[n], run.dec.theirs[n] = firstGcd(steps[1].H), d.key
                    -- a flip at a decision point: the icon changed since the tick's poll, no cast, spend, avoid or
                    -- aura change between
                    local moved = pollEv.cast or pollEv.spend or pollEv.avoid or pollEv.aura
                    if tickPolled and not moved and lastGcd ~= nil and run.dec.ours[n] ~= lastGcd then
                        run.dec.flips = run.dec.flips + 1
                    end
                end
                tickPolled = false
            end
        end
        t = t + tick
        step(t)
        if R then
            lastGcd, tickPolled = firstGcd(steps[1].H), true
        end
        run.ticks = run.ticks + 1
        local inCombat = t >= wo.pull
        local gcdFree = us.gcdUntil <= t
        -- the oracle's self-check (§4), before this tick's press: its believed power is the true power, its target
        -- debuffs the world's
        for _, st in ipairs(steps) do
            if st.plain then
                local VS = st.H.ns.VirtualState
                local now = st.base + t
                local p = VS.Power(L.power.type, now)
                if math.abs(p.est - us.power) > 1e-6 then
                    run.selfCheck.power = (run.selfCheck.power or 0) + 1
                end
                local tgt = us.target
                local debuff = st.H.ns.Facade.C_UnitAuras.GetDebuffDataByIndex -- what Hekili's aura scan reads
                for _, u in ipairs(L.uptime) do
                    local a = tgt and tgt.auras[u[2]]
                    local seen
                    for i = 1, 40 do
                        local d = debuff("target", i)
                        if not d then
                            break
                        elseif d.spellId == u[2] then
                            seen = d
                        end
                    end
                    -- up: expiring after this tick, on each side's clock (a tick and an expiry can meet within a ulp)
                    local up = a ~= nil and a.expires > t + 1e-6
                    local upSeen = seen ~= nil and seen.expirationTime > now + 1e-6
                    if up ~= upSeen or (up and a.stacks ~= seen.applications) then
                        run.selfCheck[u[1]] = (run.selfCheck[u[1]] or 0) + 1
                    end
                end
            end
        end
        -- the press policy (§2.2 step 6): the driver's first icon, once it has shown as ready for `o.reaction` s
        local q = steps[1].q
        local key = q.name[1]
        local gcdPress, refusedKey, pressedKey = false, false, false
        local shown = not R and key and q.time[1] <= (o.react or M.REACT)
        if shown then
            readySince[key] = readySince[key] or t
        end
        for k in pairs(readySince) do
            if k ~= key or not shown then
                readySince[k] = nil
            end
        end
        if shown and t - readySince[key] >= (o.reaction or 0) - 1e-9 then -- one attempt a tick
            truth.Hekili.State.reset("Primary", true) -- Update leaves its last prediction (a predicted buff, query_time ahead of now)
            local p = content.resolve(key, truth)
            local pre = W.res(us, p.pt)
            local ok, why = W.press(us, key, p)
            if inCombat then
                run.attempts = run.attempts + 1
                if steps[2] and M.readyShort(pre, p, us, t) then
                    run.readyShort = run.readyShort + 1
                end
            end
            if ok then
                run.presses = run.presses + 1
                gcdPress, pressedKey = not p.offGcd, key
            else
                if inCombat then -- over the in-combat attempts (per100)
                    run.refused[why] = (run.refused[why] or 0) + 1
                    if M.unmatched(key, steps[2] and steps[2].q, o.react or M.REACT) then
                        run.unmatched[why] = (run.unmatched[why] or 0) + 1
                    end
                end
                refusedKey = key
                if inCombat and lastRefused ~= key then
                    run.episodes = run.episodes + 1 -- a refusal episode: consecutive refused ticks of one key
                end
            end
        end
        lastRefused = refusedKey
        if inCombat then
            local n = run.combat + 1
            run.combat = n
            run.full = run.full + (us.power >= us.powerMax and 1 or 0)
            run.idle = run.idle + ((gcdFree and not gcdPress) and 1 or 0)
            local tgt = us.target
            for _, u in ipairs(L.uptime) do
                run.up[u[1]] = (run.up[u[1]] or 0) + ((tgt and tgt.auras[u[2]]) and 1 or 0)
            end
            run.ours[n] = steps[1].q.name[1]
            local out = steps[1].H.Hekili.Engine.Output.Primary
            if out.count > 0 and out.recs[1].focus then
                run.focus = run.focus + 1
            end
            run.pressed[n] = pressedKey -- the driver's own press this tick (loop.flips)
            if R then
                run.theirs[n] = R.next(t)
            else
                run.theirs[n] = steps[2] and steps[2].q.name[1] or false
                -- the shadow presses nothing: the press its policy would make, its first icon shown ready
                local sq = steps[2] and steps[2].q
                run.shadowPress[n] = sq and sq.name[1] and sq.time[1] <= (o.react or M.REACT) and sq.name[1] or false
            end
            for k = 1, #run.frames do -- the ledger's frame (flicker.frame)
                local st = steps[k]
                local f, sq = run.frames[k], st.q
                local VS = st.H.ns.VirtualState
                local now = st.base + t
                local cd = {}
                for s = 1, flicker.SLOTS do
                    f.name[s][n], f.wait[s][n], f.cost[s][n] = sq.name[s], sq.time[s], sq.cost[s]
                    cooldown(cd, st.H, sq.name[s], now)
                    cooldown(cd, st.H, n > 1 and f.name[s][n - 1], now)
                end
                local p = VS.Power(L.power.type, now)
                f.lo[n], f.est[n], f.hi[n], f.truth[n] = p.lo, p.est, p.hi, us.power
                f.pend[n] = VS.SwingPending(1) > 0 or VS.SwingPending(2) > 0
                f.cd[n], f.gcd[n], f.t[n], f.n = cd, math.max(0, us.gcdUntil - t), t, n
            end
            for _, key in ipairs(ledger and flicker.EVENTS or {}) do
                run.ev[key][n], tickEv[key] = tickEv[key], false
            end
            if steps[2] and run.ours[n] ~= run.theirs[n] then -- the belief's power error where they disagree
                local VS = steps[1].H.ns.VirtualState
                run.gap[#run.gap + 1] = VS.Power(L.power.type, steps[1].base + t).est - us.power
            end
        end
        if o.on then
            o.on(run, steps, t)
        end
    end
    -- the out-of-combat gap: each instance's clock moves past the fight, after the last tick's own events (a kill by
    -- this tick's press, and the combat end it brings: else the next fight starts in combat for the instance); our cast
    -- still running ends there (fix 31 G3: its start would be the next fight's GCD anchor), after the last tick's metrics
    W.endCasts(us)
    -- a kill's combat end comes 1 s on (observer.COMBAT_END): fed up to it, on the tick grid (a clock off the grid
    -- reorders the next fights' float sums: Feral's flicker 2.12 -> 2.34 with the gap ending at the kill + 1 s)
    local tEnd = t
    while W.killAt and tEnd < W.killAt + observer.COMBAT_END do
        tEnd = tEnd + tick
    end
    for i, st in ipairs(steps) do
        feed(st.H, st.obs, tEnd, st.base, st.sink)
        st.H.ctl.now = st.base + tEnd
        if not headless.cycle(st.H, st.H.ctl.now) then
            run.raises = run.raises + 1
        end
        if traced[i] then
            st.H.Hekili.Debug, st.H.Hekili.SaveDebugSnapshot = traced[i][1], traced[i][2]
        end
        for name, n in pairs(st.H.ns.Facade.secrets) do
            run.secrets[name] = (run.secrets[name] or 0) + n
        end
    end
    run.damage = 0 -- our true damage dealt (white wounds count at their land)
    for _, ev in ipairs(W.truth) do
        if ev.src == us and ev.act == "WOUND" and ev.kind ~= "swing" then
            run.damage = run.damage + (ev.amount or 0)
        end
    end
    run.errors, run.misses = 0, {}
    for i, st in ipairs(steps) do
        run.errors = run.errors + #st.H.errors - errors0[i]
        for _, name in ipairs(headless.unexpected(st.H, "run")) do
            run.misses[#run.misses + 1] = name
        end
    end
    run.t = t
    if not R then
        local c = { power = M.rest(W, us, us.pt, us.power, wo.decay, us.powerMax), res = {} }
        for pt, r in pairs(us.res) do
            c.res[pt] = M.rest(W, us, pt, r.cur, wo.decay, r.max)
        end
        L.carry = L.carry or {}
        L.carry[drivers[1].H] = c
    end
    return run
end

--- Fight `seed`: run A (ours drives, the oracle shadows) and run B (the oracle drives a fresh world of the same seed).
function M.fight(L, seed, o)
    local a = M.run(L, seed, o, { { H = L.us }, { H = L.oracle, plain = true } })
    local b = M.run(L, seed, o, { { H = L.oracle, plain = true } })
    return a, b
end

-- Flicker: A -> B -> A within 3 ticks in a first-icon sequence, unless the instance pressed B at the tick it showed or
-- the next (`press[i]`: the key it pressed at in-combat tick i, false none; nil, a replay: no presses). Owner rule
-- 2026-10-26: a show-then-press within one tick is not jitter (a proc at a hard cast's landing, pressed at once).
local function flips(seq, n, press)
    local f = 0
    for i = 1, n - 2 do
        local b = seq[i + 1]
        if seq[i] ~= b and seq[i + 2] == seq[i] and not (press and (press[i + 1] == b or press[i + 2] == b)) then
            f = f + 1
        end
    end
    return f
end

-- Cycles to react (§5.1): for each change of the oracle's first icon to X lasting >= 2 ticks, the ticks until ours
-- shows X, censored at the oracle's next change (-1: never). Appends to `out`.
local function reactions(ours, theirs, n, out)
    for i = 2, n - 1 do
        local x = theirs[i]
        if x and x ~= theirs[i - 1] and theirs[i + 1] == x then
            local d = -1
            for j = i, n do
                if theirs[j] ~= x then
                    break
                elseif ours[j] == x then
                    d = j - i
                    break
                end
            end
            out[#out + 1] = d
        end
    end
end

--- An empty tally (M.tally's and M.replay's).
local function blank()
    local m = {
        fights = 0,
        both = 0,
        agree = 0,
        conf = {},
        react = {},
        refused = {},
        attempts = 0,
        episodes = 0,
        readyShort = 0,
    }
    m.unmatched = {} -- run A's refusals the oracle shadow would not have made (M.unmatched)
    m.refusedB, m.attemptsB = {}, 0 -- the oracle's own, driving run B (the projection's share: §5.2 as built)
    m.A = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
    m.B = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
    m.oracleFlicker, m.errors, m.raises, m.misses, m.secrets, m.selfCheck = 0, 0, 0, {}, {}, 0
    m.cpu, m.gap, m.focus = {}, {}, 0
    m.ratio, m.cal = {}, {} -- per counted tick its cpu over its run's calibration; per counted run the calibration ms
    m.bytes, m.sampled = 0, 0 -- allocated over the sampled ticks (M.BYTES_EVERY)
    m.led = { ours = flicker.merge(), oracle = flicker.merge() } -- run A's ledgers (flicker.ledger): ours, the shadow's
    return m
end

--- `n` fights (seeds 1..n, from `o.seed0` + 1) on `L`'s boot: run A and run B each, tallied (§5.1). The first fight
--- runs traced when `o.trace` is unset (one per scenario: the facade's secret passthroughs), and adds no cpu sample
--- (the debug pass's cost is not runtime). Returns the tally; its
--- `focus` (run A's in-combat ticks whose first record of ours has `focus` set) shows a pack's flagged lines ran.
function M.tally(L, n, o)
    o = o or {}
    local m = blank()
    local lo = { tick = 1 / (o.hz or 5), react = o.react or M.REACT }
    if o.hold == nil then
        m.hold = M.HOLD
    else
        m.hold = o.hold
    end
    m.steady = o.steady
    if m.steady == nil then
        m.steady = M.STEADY
    end
    if m.steady == 0 then
        m.steady = false
    end
    for f = 1, n do
        local seed = (o.seed0 or 0) + f
        local po = setmetatable({ trace = o.trace == nil and f == 1 or o.trace }, { __index = o })
        local a, b = M.fight(L, seed, po)
        m.fights = m.fights + 1
        for i = 1, a.combat do
            local x, y = a.ours[i], a.theirs[i]
            if x and y then
                m.both = m.both + 1
                if x == y then
                    m.agree = m.agree + 1
                else
                    local key = y .. " -> " .. x
                    m.conf[key] = (m.conf[key] or 0) + 1
                end
            end
        end
        reactions(a.ours, a.theirs, a.combat, m.react)
        for why, k in pairs(a.refused) do
            m.refused[why] = (m.refused[why] or 0) + k
        end
        for why, k in pairs(a.unmatched) do
            m.unmatched[why] = (m.unmatched[why] or 0) + k
        end
        m.attempts, m.episodes = m.attempts + a.attempts, m.episodes + a.episodes
        m.readyShort = m.readyShort + a.readyShort
        m.focus = m.focus + a.focus
        for why, k in pairs(b.refused) do
            m.refusedB[why] = (m.refusedB[why] or 0) + k
        end
        m.attemptsB = m.attemptsB + b.attempts
        m.oracleFlicker = m.oracleFlicker + flips(a.theirs, a.combat, a.shadowPress)
        m.led.ours = flicker.merge(m.led.ours, flicker.ledger(a.frames[1], lo))
        m.led.oracle = flicker.merge(m.led.oracle, flicker.ledger(a.frames[2], lo))
        for side, r in pairs({ A = a, B = b }) do
            local s = m[side]
            s.combat, s.full, s.idle = s.combat + r.combat, s.full + r.full, s.idle + r.idle
            s.damage, s.time = s.damage + r.damage, s.time + r.combat / (o.hz or 5)
            s.flicker = s.flicker + flips(r.ours, r.combat, r.pressed)
            for key, k in pairs(r.up) do
                s.up[key] = (s.up[key] or 0) + k
            end
        end
        for _, r in ipairs({ a, b }) do
            m.errors, m.raises = m.errors + r.errors, m.raises + r.raises
            for _, name in ipairs(r.misses) do
                m.misses[name] = true
            end
            for name in pairs(r.secrets) do
                m.secrets[name] = true
            end
            for _, k in pairs(r.selfCheck) do
                m.selfCheck = m.selfCheck + k
            end
        end
        for _, ms in ipairs(a.cpu) do
            m.cpu[#m.cpu + 1] = ms
            m.ratio[#m.ratio + 1] = ms / a.cal
        end
        m.cal[#m.cal + 1] = a.cal
        m.bytes, m.sampled = m.bytes + a.bytes, m.sampled + a.sampled
        for _, g in ipairs(a.gap) do
            m.gap[#m.gap + 1] = g
        end
    end
    return m
end

M.blank = blank
M.flips = flips

--- One replay of wowsims log `R` (replay.lua) on `L`'s boot: ours alone on the log's world, no presses, wowsims's
--- next cast as `theirs` each tick. A tally for summary and line: the per-tick agreement with wowsims's next cast
--- (reported) and `dec` { both, agree, conf } (our first on-GCD icon just before each on-GCD cast of wowsims's).
function M.replay(L, R, o)
    local a = M.run(L, 1, setmetatable({ replay = R, trace = false }, { __index = o or {} }), { { H = L.us } })
    local m = blank()
    m.fights = 1
    for i = 1, a.combat do
        local x, y = a.ours[i], a.theirs[i]
        if x and y then
            m.both = m.both + 1
            if x == y then
                m.agree = m.agree + 1
            else
                local key = y .. " -> " .. x
                m.conf[key] = (m.conf[key] or 0) + 1
            end
        end
    end
    reactions(a.ours, a.theirs, a.combat, m.react)
    local s = m.A
    s.combat, s.full, s.idle, s.damage, s.time = a.combat, a.full, a.idle, a.damage, a.combat / (o and o.hz or 5)
    s.flicker = flips(a.ours, a.combat)
    m.B = s -- one side: a replay has no oracle run (the line's A/B fields read 1)
    m.errors, m.raises, m.cpu = a.errors, a.raises, a.cpu
    m.cal[1], m.bytes, m.sampled = a.cal, a.bytes, a.sampled
    for i, ms in ipairs(a.cpu) do
        m.ratio[i] = ms / a.cal
    end
    for _, name in ipairs(a.misses) do
        m.misses[name] = true
    end
    local tick = 1 / (o and o.hz or 5)
    m.led.ours = flicker.ledger(a.frames[1], { tick = tick, react = o and o.react or M.REACT })
    -- the decision points' flips (loop.run) and our unjustified retracted readies that wowsims's own cast of that
    -- ability within a tick confirms as wrong
    m.dec = { both = 0, agree = 0, conf = {}, flips = a.dec.flips, confirmed = 0 }
    m.hold = M.HOLD
    if o and o.hold ~= nil then
        m.hold = o.hold
    end
    m.steady = M.STEADY
    if o and o.steady ~= nil then
        m.steady = o.steady
    end
    if m.steady == 0 then
        m.steady = false
    end
    for _, e in ipairs(m.led.ours.entries) do
        if e.kind == "retracted" and not e.justified then
            local te = a.frames[1].t[e.tick]
            for _, d in ipairs(R.decisions) do
                if d.key == e.from and math.abs(d.t - te) <= tick + 1e-9 then
                    m.dec.confirmed = m.dec.confirmed + 1
                    break
                end
            end
        end
    end
    for i, y in ipairs(a.dec.theirs) do
        local x = a.dec.ours[i]
        m.dec.both = m.dec.both + 1
        if x == y then
            m.dec.agree = m.dec.agree + 1
        else
            local key = y .. " -> " .. tostring(x)
            m.dec.conf[key] = (m.dec.conf[key] or 0) + 1
        end
    end
    return m
end

-- The `p` quantile of a list (sorted in place).
local function quantile(list, p)
    table.sort(list)
    return list[math.max(1, math.ceil(p * #list))] or 0
end

--- The tally's derived metrics: agreement, react (median, p90, share never; in ticks), refusals per 100 attempts by
--- reason (per100; per100U the unmatched ones, M.unmatched; per100B the oracle's own in run B), episodes per minute, damage per second A / B, full-power and GCD-idle shares and debuff uptimes (A, B),
--- flicker per minute (ours, the oracle's), CPU per Update (mean, p99 ms; cpuRatio the mean of each tick's ms over its
--- run's calibration, calMean the calibration's mean ms; bytes allocated per Update, sampled, reported only), and
--- the tally's focus count (not in M.line).
function M.summary(m)
    local r = { focus = m.focus, readyShort = m.readyShort or 0 }
    r.agreement = m.agree / math.max(1, m.both)
    local reacted, never = {}, 0
    for _, d in ipairs(m.react) do
        if d < 0 then
            never = never + 1
        else
            reacted[#reacted + 1] = d
        end
    end
    r.reactMedian, r.reactP90 = quantile(reacted, 0.5), quantile(reacted, 0.9)
    r.never = never / math.max(1, #m.react)
    r.per100, r.per100B, r.per100U = {}, {}, {}
    for why, k in pairs(m.refused) do
        r.per100[why] = 100 * k / math.max(1, m.attempts)
        r.per100U[why] = 100 * (m.unmatched[why] or 0) / math.max(1, m.attempts)
    end
    for why, k in pairs(m.refusedB) do
        r.per100B[why] = 100 * k / math.max(1, m.attemptsB)
    end
    local minutes = m.A.time / 60
    r.episodes = m.episodes / math.max(1e-9, minutes)
    r.dps = (m.A.damage / math.max(1e-9, m.A.time)) / math.max(1e-9, m.B.damage / math.max(1e-9, m.B.time))
    for _, side in ipairs({ "A", "B" }) do
        local s = m[side]
        r["full" .. side], r["idle" .. side] = s.full / math.max(1, s.combat), s.idle / math.max(1, s.combat)
        r["up" .. side] = {}
        for key, k in pairs(s.up) do
            r["up" .. side][key] = k / math.max(1, s.combat)
        end
    end
    r.flicker, r.oracleFlicker = m.A.flicker / math.max(1e-9, minutes), m.oracleFlicker / math.max(1e-9, minutes)
    r.led, r.ledO = flicker.summary(m.led.ours, minutes), flicker.summary(m.led.oracle, minutes)
    r.retracted, r.retractedO = r.led.retracted, r.ledO.retracted
    local sum = 0
    for _, ms in ipairs(m.cpu) do
        sum = sum + ms
    end
    r.cpuMean, r.cpuP99 = sum / math.max(1, #m.cpu), quantile(m.cpu, 0.99)
    sum = 0
    for _, x in ipairs(m.ratio) do
        sum = sum + x
    end
    r.cpuRatio = sum / math.max(1, #m.ratio)
    sum = 0
    for _, ms in ipairs(m.cal) do
        sum = sum + ms
    end
    r.calMean = sum / math.max(1, #m.cal)
    r.bytes = m.bytes / math.max(1, m.sampled)
    if m.dec then
        r.decisions = m.dec.agree / math.max(1, m.dec.both)
    end
    return r
end

-- A confusion table's top three disagreements, "key count" joined by "; ".
local function top3(conf)
    local list = {}
    for key, k in pairs(conf) do
        list[#list + 1] = { key, k }
    end
    table.sort(list, function(x, y)
        return x[2] > y[2] or (x[2] == y[2] and x[1] < y[1])
    end)
    local top = {}
    for i = 1, math.min(3, #list) do
        top[i] = list[i][1] .. " " .. list[i][2]
    end
    return table.concat(top, "; ")
end

--- One line for a failure message: the summary, the confusion table's top three disagreements (oracle -> ours) and
--- the believed power minus the truth where they disagree (mean), reported, never gated.
--- The refusal list of a summary, every reason either side has.
function M.refusedLine(r)
    local keys, refused = {}, {}
    for why in pairs(r.per100) do
        keys[why] = true
    end
    for why in pairs(r.per100B) do
        keys[why] = true
    end
    for why in pairs(keys) do
        refused[#refused + 1] = ("%s %.1f (oracle %.1f, unmatched %.1f)"):format(
            why,
            r.per100[why] or 0,
            r.per100B[why] or 0,
            r.per100U[why] or 0
        )
    end
    table.sort(refused)
    return table.concat(refused, ", ")
end

function M.line(m)
    local r = M.summary(m)
    local up = {}
    for key, v in pairs(r.upA) do
        up[#up + 1] = ("%s %.2f/%.2f"):format(key, v, r.upB[key] or 0)
    end
    table.sort(up)
    local gap = 0
    for _, g in ipairs(m.gap) do
        gap = gap + g
    end
    local line = (
        "fights=%d agreement %.3f (%d ticks); react median %d p90 %d never %.3f; ready while short %d; refused per 100 [%s], episodes %.2f/min; "
        .. "dps A/B %.3f; full %.3f/%.3f idle %.3f/%.3f; uptime [%s]; flicker %.2f/min (oracle %.2f); "
        .. "errors %d raises %d self-check %d; cpu mean %.2f p99 %.2f ms ratio %.3f (calibration %.2f ms) "
        .. "bytes %.0f per Update; top [%s]; power est-truth at disagreements %.1f"
    ):format(
        m.fights,
        r.agreement,
        m.both,
        r.reactMedian,
        r.reactP90,
        r.never,
        r.readyShort,
        M.refusedLine(r),
        r.episodes,
        r.dps,
        r.fullA,
        r.fullB,
        r.idleA,
        r.idleB,
        table.concat(up, ", "),
        r.flicker,
        r.oracleFlicker,
        m.errors,
        m.raises,
        m.selfCheck,
        r.cpuMean,
        r.cpuP99,
        r.cpuRatio,
        r.calMean,
        r.bytes,
        top3(m.conf),
        gap / math.max(1, #m.gap)
    )
    if m.dec then -- a replay's headline (loop.replay): every other line is unchanged
        line = line .. ("; decisions on-GCD %.3f (%d) top [%s]"):format(r.decisions, m.dec.both, top3(m.dec.conf))
        line = line
            .. ("; decision flips %d (%.1f per 100), retracted confirmed by wowsims %d"):format(
                m.dec.flips,
                100 * m.dec.flips / math.max(1, m.dec.both),
                m.dec.confirmed
            )
    end
    line = line .. "; " .. flicker.line(r.led, r.ledO) -- the flicker ledger's fields, last (layout.md's columns)
    if m.hold then
        line = line .. "; hold on"
    end
    if m.steady then
        line = line
            .. "; steady icons on"
            .. (type(m.steady) == "number" and m.steady > 1 and " (hold " .. m.steady .. ")" or "")
    end
    return line
end

return M
