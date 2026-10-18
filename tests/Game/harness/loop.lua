-- tests/Game/harness/loop.lua (headless loop design §2, §4): stock Hekili pressing its own first icon against the
-- harness's world. Two instances in lockstep on one world (§2.2): ours, reading the Forever client the observer
-- encodes, and the oracle, reading a secret-free client (k.plain, design §4/D4) with the target's health rows raw.
-- Run A: ours drives, the oracle shadows; run B: the same seed, a fresh world, the oracle drives (§2.3).
-- Class-neutral (the boundary rule): the content passes the character, the pack, the press resolution, the usability
-- answers, the true power gain per hit (content.gain, for the content's power type), the world's knobs and the debuff
-- list.
local headless = require("Game.harness.headless")
local observer = require("Game.harness.observer")
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")

local M = {}

M.TICK = 0.2 -- 5 Hz, the in-game combat rate (D1); o.hz = 10 the option
M.REACT = 0.05 -- a first icon whose wait is at most this is shown as ready: pressed
M.PULL = 3 -- the world starts this long before the pull, the target selected (precombat presses)
M.GAP = 30 -- out of combat between two fights on one boot (consecutive pulls)
-- The oracle's facade rows answered by the client (§4's override): the target's health, and the debuff row Hekili's
-- aura scan reads (raw since VirtualState counted a modelled stack on top of a plain read that arrived before the
-- cast's drain, fixed in Auras.lua's I.AuraModel and pinned in loop_warrior_spec). The buff row stays VirtualState's: our
-- forms become buffs in the belief, and the client's list does not hold them.
M.RAW = { "UnitHealth", "UnitHealthMax", "C_UnitAuras.GetDebuffDataByIndex" }

--- Boots the two instances for `content` (one boot per busted block, §1.3): { content, us, oracle }. `content`:
--- character(), PACK, resolve(key, H), usable(H), gain(pt, hand, amount, flag) (what a landed wound of ours pays in
--- power type `pt`, the character's), WORLD (scenario knobs), uptime(H); optional OBSERVE (observer knobs over the
--- loop's: another power's reads, the forms).
function M.new(content)
    local L = { content = content }
    local character = content.character()
    L.form, L.power = character.form, character.power
    local pt = L.power.type
    L.gain = function(hand, amount, flag) -- the swing-paid power is the character's (scenarios.world's `pt`)
        return content.gain(pt, hand, amount, flag)
    end
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
    local out = H.Hekili.Engine.Output.Primary
    local k = math.min(n, out.count)
    for i = 1, k do
        local r = out.recs[i]
        q.name[i], q.time[i] = r.actionName, r.time or 0
    end
    for i = k + 1, n do
        q.name[i], q.time[i] = false, 0
    end
    return k
end

--- One run of fight `seed`: the instances in `drivers` (each { H, plain }) stepped on one world in lockstep, the
--- first one's first icon pressed. `o`: duration (combat seconds [180]), mobHealth, hz [5], react [REACT], reaction
--- (seconds an icon shows ready before the press [0]), others (archetypes on our target), trace (the facade's trace
--- each tick), on(run, steps, t) (a per-tick hook). Returns the run { W, us, ticks, presses, refused (by reason),
--- attempts, episodes, errors, raises, misses (unexpected run names), secrets (Facade.secrets), selfCheck (ticks where
--- the oracle's belief missed the truth, by field), combat, full, idle, up (by debuff key: in-combat ticks), ours and
--- theirs (first icons by in-combat tick), focus (in-combat ticks whose first record of ours has `focus` set), gap (believed minus true power where they differ), cpu (ms per tick of
--- the first instance, timed around headless.cycle: VirtualState's flush and the timers as well as Update, so it errs
--- high), damage, t }.
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
    local W = scenarios.world(wo, seed)
    local us = W.ents[1]
    local run = { W = W, us = us, ticks = 0, presses = 0, refused = {}, raises = 0, selfCheck = {} }
    -- the metrics' per-tick record (§5.1): in-combat ticks only, both queues' first icons, the truth
    run.combat, run.full, run.idle, run.attempts, run.episodes, run.up = 0, 0, 0, 0, 0, {}
    run.ours, run.theirs, run.gap, run.cpu, run.secrets, run.focus = {}, {}, {}, {}, {}, 0
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
        -- UnitLevel is plain in combat on Forever (the facade's passthrough row); fake_api answers an unset unit secret
        -- `targetLevel` the content's answer for the target (-1: a boss, as Hekili's `boss` reads it)
        ctl.level.target, ctl.level.nameplate1 = wo.targetLevel or wo.level, wo.targetLevel or wo.level
        local k = setmetatable({
            usable = L.answers,
            gcdSpell = d.H.ns.VirtualStateInternal.GCD_SPELL,
            powerType = L.power.type, -- the content's power, not the observer's default
            powerToken = L.power.token,
        }, {
            __index = observer.DEFAULTS,
        })
        for key, v in pairs(content.OBSERVE or {}) do -- the content's client knobs (other powers' reads, forms)
            k[key] = v
        end
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
    local lastRefused, readySince = false, {}
    local traced = {}
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
    while t < stopAt and not W.killAt do
        t = t + tick
        W.run(t)
        for i, st in ipairs(steps) do
            feed(st.H, st.obs, t, st.base, sink)
            st.H.Hekili.ActiveDebug = o.trace or false
            local c0 = os.clock()
            local ok = headless.cycle(st.H, st.base + t)
            if i == 1 then
                run.cpu[#run.cpu + 1] = (os.clock() - c0) * 1000
            end
            st.H.Hekili.ActiveDebug = false
            if not ok then
                run.raises = run.raises + 1
            end
            queue(st.H, st.q, 3)
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
        local gcdPress, refusedKey = false, false
        local shown = key and q.time[1] <= (o.react or M.REACT)
        if shown then
            readySince[key] = readySince[key] or t
        end
        for k in pairs(readySince) do
            if k ~= key or not shown then
                readySince[k] = nil
            end
        end
        if shown and t - readySince[key] >= (o.reaction or 0) - 1e-9 then -- one attempt a tick
            local p = content.resolve(key, L.oracle)
            local ok, why = W.press(us, key, p)
            if inCombat then
                run.attempts = run.attempts + 1
            end
            if ok then
                run.presses = run.presses + 1
                gcdPress = not p.offGcd
            else
                if inCombat then -- over the in-combat attempts (per100)
                    run.refused[why] = (run.refused[why] or 0) + 1
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
            run.theirs[n] = steps[2] and steps[2].q.name[1] or false
            if steps[2] and run.ours[n] ~= run.theirs[n] then -- the belief's power error where they disagree
                local VS = steps[1].H.ns.VirtualState
                run.gap[#run.gap + 1] = VS.Power(L.power.type, steps[1].base + t).est - us.power
            end
        end
        if o.on then
            o.on(run, steps, t)
        end
    end
    -- the out-of-combat gap: each instance's clock moves past the fight
    for i, st in ipairs(steps) do
        st.H.ctl.now = st.base + t
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
    return run
end

--- Fight `seed`: run A (ours drives, the oracle shadows) and run B (the oracle drives a fresh world of the same seed).
function M.fight(L, seed, o)
    local a = M.run(L, seed, o, { { H = L.us }, { H = L.oracle, plain = true } })
    local b = M.run(L, seed, o, { { H = L.oracle, plain = true } })
    return a, b
end

-- A -> B -> A within 3 ticks in a first-icon sequence.
local function flicker(seq, n)
    local f = 0
    for i = 1, n - 2 do
        if seq[i] ~= seq[i + 1] and seq[i + 2] == seq[i] then
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

--- `n` fights (seeds 1..n, from `o.seed0` + 1) on `L`'s boot: run A and run B each, tallied (§5.1). The first fight
--- runs traced when `o.trace` is unset (one per scenario: the facade's secret passthroughs). Returns the tally; its
--- `focus` (run A's in-combat ticks whose first record of ours has `focus` set) shows a pack's flagged lines ran.
function M.tally(L, n, o)
    o = o or {}
    local m = { fights = 0, both = 0, agree = 0, conf = {}, react = {}, refused = {}, attempts = 0, episodes = 0 }
    m.refusedB, m.attemptsB = {}, 0 -- the oracle's own, driving run B (the projection's share: §5.2 as built)
    m.A = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
    m.B = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
    m.oracleFlicker, m.errors, m.raises, m.misses, m.secrets, m.selfCheck = 0, 0, 0, {}, {}, 0
    m.cpu, m.gap, m.focus = {}, {}, 0
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
        m.attempts, m.episodes = m.attempts + a.attempts, m.episodes + a.episodes
        m.focus = m.focus + a.focus
        for why, k in pairs(b.refused) do
            m.refusedB[why] = (m.refusedB[why] or 0) + k
        end
        m.attemptsB = m.attemptsB + b.attempts
        m.oracleFlicker = m.oracleFlicker + flicker(a.theirs, a.combat)
        for side, r in pairs({ A = a, B = b }) do
            local s = m[side]
            s.combat, s.full, s.idle = s.combat + r.combat, s.full + r.full, s.idle + r.idle
            s.damage, s.time = s.damage + r.damage, s.time + r.combat / (o.hz or 5)
            s.flicker = s.flicker + flicker(r.ours, r.combat)
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
        end
        for _, g in ipairs(a.gap) do
            m.gap[#m.gap + 1] = g
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
--- reason, episodes per minute, damage per second A / B, full-power and GCD-idle shares and debuff uptimes (A, B),
--- flicker per minute (ours, the oracle's), CPU per Update (mean, p99 ms), and the tally's focus count (not in M.line).
function M.summary(m)
    local r = { focus = m.focus }
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
    r.per100, r.per100B = {}, {}
    for why, k in pairs(m.refused) do
        r.per100[why] = 100 * k / math.max(1, m.attempts)
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
    local sum = 0
    for _, ms in ipairs(m.cpu) do
        sum = sum + ms
    end
    r.cpuMean, r.cpuP99 = sum / math.max(1, #m.cpu), quantile(m.cpu, 0.99)
    return r
end

--- One line for a failure message: the summary, the confusion table's top three disagreements (oracle -> ours) and
--- the believed power minus the truth where they disagree (mean), reported, never gated.
function M.line(m)
    local r = M.summary(m)
    local conf = {}
    for key, k in pairs(m.conf) do
        conf[#conf + 1] = { key, k }
    end
    table.sort(conf, function(x, y)
        return x[2] > y[2] or (x[2] == y[2] and x[1] < y[1])
    end)
    local top = {}
    for i = 1, math.min(3, #conf) do
        top[i] = conf[i][1] .. " " .. conf[i][2]
    end
    local refused = {}
    for why, v in pairs(r.per100) do
        refused[#refused + 1] = ("%s %.1f (oracle %.1f)"):format(why, v, r.per100B[why] or 0)
    end
    table.sort(refused)
    local up = {}
    for key, v in pairs(r.upA) do
        up[#up + 1] = ("%s %.2f/%.2f"):format(key, v, r.upB[key] or 0)
    end
    table.sort(up)
    local gap = 0
    for _, g in ipairs(m.gap) do
        gap = gap + g
    end
    return (
        "fights=%d agreement %.3f (%d ticks); react median %d p90 %d never %.3f; refused per 100 [%s], episodes %.2f/min; "
        .. "dps A/B %.3f; full %.3f/%.3f idle %.3f/%.3f; uptime [%s]; flicker %.2f/min (oracle %.2f); "
        .. "errors %d raises %d self-check %d; cpu mean %.2f p99 %.2f ms; top [%s]; power est-truth at disagreements %.1f"
    ):format(
        m.fights,
        r.agreement,
        m.both,
        r.reactMedian,
        r.reactP90,
        r.never,
        table.concat(refused, ", "),
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
        table.concat(top, "; "),
        gap / math.max(1, #m.gap)
    )
end

return M
