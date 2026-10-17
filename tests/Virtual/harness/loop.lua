-- tests/Virtual/harness/loop.lua (headless loop design §2, §4): stock Hekili pressing its own first icon against the
-- harness's world. Two instances in lockstep on one world (§2.2): ours, reading the Forever client the observer
-- encodes, and the oracle, reading a secret-free client (k.plain, design §4/D4) with the target's health rows raw.
-- Run A: ours drives, the oracle shadows; run B: the same seed, a fresh world, the oracle drives (§2.3).
-- Class-neutral (the boundary rule): the content passes the character, the pack, the press resolution, the usability
-- answers, the true rage per hit, the world's knobs and the debuff list.
local headless = require("Virtual.harness.headless")
local observer = require("Virtual.harness.observer")
local scenarios = require("Virtual.harness.scenarios")
local drive = require("Virtual.harness.drive")

local M = {}

M.TICK = 0.2 -- 5 Hz, the in-game combat rate (D1); o.hz = 10 the option
M.REACT = 0.05 -- a first icon whose wait is at most this is shown as ready: pressed
M.PULL = 3 -- the world starts this long before the pull, the target selected (precombat presses)
M.GAP = 30 -- out of combat between two fights on one boot (consecutive pulls)
M.RAW = { "UnitHealth", "UnitHealthMax" } -- the oracle's facade rows answered by the client (target health plain)

--- Boots the two instances for `content` (one boot per busted block, §1.3): { content, us, oracle }. `content`:
--- character(), PACK, resolve(key, H), usable(H), rage(hand, amount, flag), WORLD (scenario knobs), uptime(H).
function M.new(content)
    local L = { content = content }
    local character = content.character()
    L.form = character.form
    L.us = headless.new({ character = character, pack = content.PACK })
    L.oracle = headless.new({ character = character, pack = content.PACK, raw = M.RAW })
    for _, H in ipairs({ L.us, L.oracle }) do
        H.ctl.inRange.target = true -- shortcut: no positions, every target in melee range
    end
    L.answers = content.usable(L.oracle)
    L.uptime = content.uptime(L.oracle)
    return L
end

-- Fires the client events `obs` releases up to world time `t` into instance `H`, each at its own time (base + t).
local function feed(H, obs, t, base, sink)
    local s = obs.s
    local first, last = obs.step(t)
    local ctl = H.ctl
    for i = first, last do
        ctl.now = base + s.t[i]
        local ev = s.ev[i]
        if ev:byte(1) == 64 then -- "@"; a cooldown's start and an aura's expiry on the instance's clock
            local a2, a4 = s.a2[i], s.a4[i]
            if ev == "@cooldown" and type(a2) == "number" and a2 > 0 then
                a2 = base + a2
            elseif ev == "@aura" and a4 > 0 then
                a4 = base + a4
            end
            drive.op(sink, ctl, ev, s.a1[i], a2, s.a3[i], a4, s.a5[i])
        else
            H.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
        end
    end
end

-- The first `n` entries of an instance's Primary queue into `q` (names, waits); returns how many.
local function queue(H, q, n)
    local recs = H.ns.UI.Displays.Primary.Recommendations
    local k = 0
    for i = 1, n do
        local r = recs[i]
        if r and r.actionName then
            k = k + 1
            q.name[k], q.time[k] = r.actionName, r.time or 0
        end
    end
    for i = k + 1, n do
        q.name[i], q.time[i] = false, 0
    end
    return k
end

--- One run of fight `seed`: the instances in `runners` (each { H, obs knobs }) stepped on one world in lockstep, the
--- first one's first icon pressed. `o`: duration (combat seconds [180]), mobHealth, hz [5], react [REACT], on(tick)
--- (a per-tick hook for the metrics). Returns the run { W, us, ticks, presses, refused (by reason), errors, raises,
--- misses (unexpected run names), selfCheck (ticks where the oracle's belief missed the truth, by field) }.
function M.run(L, seed, o, drivers)
    o = o or {}
    local content = L.content
    local tick = 1 / (o.hz or 5)
    local wo = setmetatable({
        pull = M.PULL,
        prepull = 0.1,
        duration = o.duration or 180,
        mobHealth = o.mobHealth or content.WORLD.mobHealth,
        rage = content.rage,
        form = L.form,
        tag = "-" .. seed .. "-" .. #drivers, -- a fresh mob per run
    }, { __index = content.WORLD })
    local W = scenarios.world(wo, seed)
    local us = W.ents[1]
    local run = { W = W, us = us, ticks = 0, presses = 0, refused = {}, raises = 0, selfCheck = {} }
    local sink = {}
    local steps = {}
    for i, d in ipairs(drivers) do
        local ctl = d.H.ctl -- a fresh world: the client's answers about it start fresh too
        ctl.combat, ctl.form = false, L.form
        for _, t in ipairs({ ctl.dead, ctl.current, ctl.cooldown, ctl.usable, ctl.unitHealth, ctl.unitHealthMax }) do
            for key in pairs(t) do
                t[key] = nil
            end
        end
        for _, list in pairs(ctl.auras) do
            list.HELPFUL, list.HARMFUL = {}, {}
        end
        ctl.auraError.target = nil
        local k = setmetatable({ usable = L.answers, gcdSpell = d.H.ns.VirtualStateInternal.GCD_SPELL }, {
            __index = observer.DEFAULTS,
        })
        if d.plain then
            k.plain, k.usableDelay = true, 0
        end
        local base = d.H.ctl.now + M.GAP -- this instance's clock continues from its last fight
        steps[i] = { H = d.H, obs = observer.new(W, k), base = base, q = { name = {}, time = {} }, plain = d.plain }
    end
    local errors0 = {}
    for i, st in ipairs(steps) do
        errors0[i] = #st.H.errors
    end
    local stopAt = W.stopAt
    local t = 0
    local lastAttempt = -1
    while t < stopAt and not W.killAt do
        t = t + tick
        W.run(t)
        for _, st in ipairs(steps) do
            feed(st.H, st.obs, t, st.base, sink)
            local ok = headless.cycle(st.H, st.base + t)
            if not ok then
                run.raises = run.raises + 1
            end
            queue(st.H, st.q, 3)
        end
        run.ticks = run.ticks + 1
        -- the oracle's self-check (§4), before this tick's press: its believed power is the true power, its target
        -- debuffs the world's
        for _, st in ipairs(steps) do
            if st.plain then
                local VS = st.H.ns.VirtualState
                local now = st.base + t
                local p = VS.Power(observer.DEFAULTS.powerType, now)
                if math.abs(p.est - us.power) > 1e-6 then
                    run.selfCheck.power = (run.selfCheck.power or 0) + 1
                end
                local tgt = us.target
                for _, u in ipairs(L.uptime) do
                    local a = tgt and tgt.auras[u[2]]
                    local exp, stacks = VS.Aura("target", u[2], now)
                    if (a ~= nil) ~= (exp ~= nil) or (a and a.stacks ~= stacks) then
                        run.selfCheck[u[1]] = (run.selfCheck[u[1]] or 0) + 1
                    end
                end
            end
        end
        -- the press policy (behaviours.recommended, §2.2 step 6): the driver's first icon, when shown as ready
        local q = steps[1].q
        local key = q.name[1]
        if key and q.time[1] <= (o.react or M.REACT) and lastAttempt < t then
            lastAttempt = t
            local oracleH = L.oracle
            local p = content.resolve(key, oracleH)
            local ok, why = W.press(us, key, p)
            if ok then
                run.presses = run.presses + 1
            else
                run.refused[why] = (run.refused[why] or 0) + 1
            end
        end
        if o.on then
            o.on(run, steps, t)
        end
    end
    -- the out-of-combat gap: each instance's clock moves past the fight
    for _, st in ipairs(steps) do
        st.H.ctl.now = st.base + t
        headless.cycle(st.H, st.H.ctl.now)
    end
    run.errors, run.misses = 0, {}
    for i, st in ipairs(steps) do
        run.errors = run.errors + #st.H.errors - errors0[i]
        for _, name in ipairs(headless.unexpected(st.H, "run")) do
            run.misses[#run.misses + 1] = name
        end
    end
    run.t = t
    return run
end

--- Fight `seed`: run A (ours drives, the oracle shadows) and run B (the oracle drives a fresh world of the same seed).
function M.fight(L, seed, o)
    local a = M.run(L, seed, o, { { H = L.us }, { H = L.oracle, plain = true } })
    local b = M.run(L, seed, o, { { H = L.oracle, plain = true } })
    return a, b
end

return M
