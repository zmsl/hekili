-- tools/ttd_lab/observe.lua: what the client lets us see of a fight. Frames every 16-33 ms; on a target change the
-- stream restarts and stays unknown for 8-12 frames (the prime); then the 1% band (lo, lo + 1; the top cell 99-100
-- holds full health) is reported in the frame a change is first seen or the next one (1-2 frames late), one call per
-- frame with the net band (a burst skips percents). Polls every 0.1-0.25 s while the target is alive carry the truth
-- and the player's own damage per second over the last 3 s (a meter, plain).
-- Output: ops (kind, t, a, b) with kind 1 restart, 2 band (a = lo, b = hi), 3 poll (a = own dps, b = poll index), 4 lust,
-- 5 combat (run 4), and
-- per poll: stream id, true time to die, true fight remaining, stream start, stream true death.
local Rng = require("rng")

local O = {}

local RESTART, BAND, POLL, LUST, COMBAT = 1, 2, 3, 4, 5
O.RESTART, O.BAND, O.POLL, O.LUST, O.COMBAT = RESTART, BAND, POLL, LUST, COMBAT
O.POST = 10 -- seconds after a rate change that count as "post-change" polls
-- Run 4: LibHiddenValues' own contract when set: full health is its own band (lo = hi = 100) and 99..100 a loss, so
-- the first damage is seen; and a COMBAT op at `fight.combat` (combat start, for the library's re-anchor). Off: the
-- runs 1-3 observation (the top cell 99-100 holds full), byte for byte.
O.lhv = false

-- Run 2 additions: a LUST op (a = multiplier, b = its end) in the first frame of a lust, for the hint-taking
-- variants (the others ignore it); per poll `post` (a rate change on this mob or every mob in the last O.POST s);
-- `execute` ({ pct, mult } or nil) for the execute-declaring variants.
local function postChange(changes, mob, t)
    for i = 1, #changes do
        local c = changes[i]
        if (c.mob == 0 or c.mob == mob) and c.t <= t and t - c.t < O.POST then
            return true
        end
    end
    return false
end

function O.build(fight, seed)
    local rng = Rng.new(seed)
    local ok, ot, oa, ob = {}, {}, {}, {}
    local polls = { stream = {}, tru = {}, fight = {}, t = {}, start = {}, death = {}, post = {}, n = 0 }
    local changes, lust, lustSent = fight.changes or {}, fight.lust, false
    local lhv, combatSent = O.lhv, false
    local function op(k, t, a, b)
        local n = #ok + 1
        ok[n], ot[n], oa[n], ob[n] = k, t, a, b
    end
    local plan, mobs, own = fight.plan, fight.mobs, fight.own
    local idx = {}
    for i = 1, #mobs do
        idx[i] = 1
    end
    local function truePct(m, t)
        local mob, i = mobs[m], idx[m]
        while mob.ht[i + 1] and mob.ht[i + 1] <= t do
            i = i + 1
        end
        idx[m] = i
        return mob.hv[i]
    end
    local pi, stream, mob, startT, prime = 1, 0, nil, nil, 0
    local trueLo, pendingAt, frame = nil, nil, 0
    local ownLo, ownHi, ownSum = 1, 0, 0
    local f, nextPoll = 0, rng:uni(0.1, 0.25)
    while f <= fight.endT + 0.05 do
        frame = frame + 1
        if fight.combat and not combatSent and f >= fight.combat then
            combatSent = true
            op(COMBAT, f)
        end
        if lust and not lustSent and f >= lust.t then
            lustSent = true
            op(LUST, f, lust.mult, lust.t + lust.dur)
        end
        while plan[pi] and plan[pi].t <= f do -- a target change: the stream restarts
            mob, startT, stream = plan[pi].mob, f, stream + 1
            prime, trueLo, pendingAt = rng:int(8, 12), nil, nil
            op(RESTART, f)
            pi = pi + 1
        end
        local alive = mob and not (mobs[mob].death and mobs[mob].death <= f)
        if alive then
            local p = truePct(mob, f)
            local lo = math.min(99, math.floor(p))
            if lhv and p >= 100 then
                lo = 100
            end
            if prime > 0 then
                prime = prime - 1
                if prime == 0 then
                    trueLo = lo
                    op(BAND, f, lo, math.min(100, lo + 1))
                end
            elseif lo ~= trueLo then
                trueLo = lo
                pendingAt = pendingAt or (frame + (rng:next() < 0.5 and 0 or 1))
            end
            if pendingAt and frame >= pendingAt then
                pendingAt = nil
                op(BAND, f, trueLo, math.min(100, trueLo + 1))
            end
        end
        while own.t[ownHi + 1] and own.t[ownHi + 1] <= f do
            ownHi = ownHi + 1
            ownSum = ownSum + own.a[ownHi]
        end
        while ownLo <= ownHi and own.t[ownLo] <= f - 3 do
            ownSum = ownSum - own.a[ownLo]
            ownLo = ownLo + 1
        end
        if f >= nextPoll then
            nextPoll = f + rng:uni(0.1, 0.25)
            if alive then
                local n = polls.n + 1
                polls.n = n
                polls.stream[n], polls.t[n], polls.start[n] = stream, f, startT
                polls.death[n] = mobs[mob].death or fight.endT
                polls.tru[n] = polls.death[n] - f
                polls.fight[n] = fight.endT - f
                polls.post[n] = postChange(changes, mob, f)
                op(POLL, f, math.max(0, ownSum) / 3, n)
            end
        end
        f = f + rng:uni(0.016, 0.033)
    end
    return {
        k = ok,
        t = ot,
        a = oa,
        b = ob,
        polls = polls,
        execute = fight.execute,
        members = fight.members,
        group = fight.group,
    }
end

--- Feeds ops to an algorithm (restart(t), band(t, lo, hi), get(now, dps, poll index) -> est or nil; optional
--- lust(t, mult, endT) and combat(t)); returns the answers per poll (false: unknown).
function O.run(obs, algo, out)
    out = out or {}
    local k, t, a, b = obs.k, obs.t, obs.a, obs.b
    for i = 1, #k do
        local kind = k[i]
        if kind == BAND then
            algo:band(t[i], a[i], b[i])
        elseif kind == POLL then
            local est = algo:get(t[i], a[i], b[i])
            if est then
                assert(est == est and est >= 0 and est < math.huge, "bad estimate")
                out[b[i]] = math.min(est, 3600)
            else
                out[b[i]] = false
            end
        elseif kind == LUST then
            if algo.lust then
                algo:lust(t[i], a[i], b[i])
            end
        elseif kind == COMBAT then
            if algo.combat then
                algo:combat(t[i])
            end
        else
            algo:restart(t[i])
        end
    end
    return out
end

return O
