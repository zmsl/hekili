-- tests/Game/harness/metrics.lua (harness design §3.3): scores a run against the world's truth. Own hits per hand
-- (credited to the right swing, to the wrong one, missed), false credits split by what they cost (a wound of another
-- source, our tick or proc credited to a swing of ours pays rage; an avoid of another source or an unexplained one
-- only mislabels a SWING_MISSED row), the rage error per 10 s window (believed est minus truth, each
-- window as if pinned at its start) and the row checks.
local M = {}

--- A fresh tally (summed over fights by `score`).
function M.new()
    return {
        fights = 0,
        swings = 0,
        own = { 0, 0 },
        right = { 0, 0 },
        wrong = { 0, 0 },
        missed = { 0, 0 },
        falseWounds = { 0, 0 }, -- another source's or an unexplained wound (or our tick or proc) credited: pays rage
        -- the same, less those the oracle retracted at their verdict: the rage they leave paid
        falseNet = { 0, 0 },
        falseAvoids = { 0, 0 }, -- another source's or an unexplained avoid credited: mislabels a row, pays nothing
        late = 0,
        windows = 0,
        over = 0,
        loOver = 0,
        estOver = 0,
        danger = 0,
        errSum = 0,
        errMax = 0,
        noDst = 0,
        order = 0,
        nonTarget = 0,
        judged = 0,
        falseJudged = 0,
        caught = 0,
        falseRetracted = 0,
        rescued = 0,
        rescuedOurs = 0,
        onusAll = 0,
        onusCredited = 0,
        onusRight = 0,
        hitsFed = 0,
        hitsStaged = 0,
        avoidRight = 0,
        avoidWrong = 0,
    }
end

-- Our true power at `t`: the last truth event with a power at or before it (0 before any).
local function truthAt(W, t)
    local p = 0
    for _, ev in ipairs(W.truth) do
        if ev.t > t then
            break
        end
        if ev.power then
            p = ev.power
        end
    end
    return p
end
M.truthAt = truthAt

--- Adds one fight (drive captures `c`, stream `s`, world `W`) to tally `m`: the outcomes from `after` seconds on (default
--- all), and only at times `keep(t)` accepts when given (a section of the fight). `step`: one main-hand step (the
--- overshoot bar, default 9). Returns `m`.
function M.score(m, c, s, W, step, after, keep)
    step, after = step or 9, after or 0
    local function inside(t)
        return t >= after and (keep == nil or keep(t))
    end
    m.fights = m.fights + 1
    for i = 1, s.n do
        local ev = s.ev[i]
        if ev == "PLAYER_SWING" and inside(s.t[i]) then -- the same window as the false credits
            m.swings = m.swings + 1
        elseif ev == "UNIT_COMBAT" and s.a1[i] == "target" and inside(s.t[i]) then
            local h, cr = s.hand[i], c.crHand[i]
            if s.src[i] == 1 and h > 0 and s.a2[i] == "WOUND" and s.a4[i] > 0 then
                m.own[h] = m.own[h] + 1
                if cr == h and c.crAt[i] == s.swingT[i] then
                    m.right[h] = m.right[h] + 1
                elseif cr > 0 then
                    m.wrong[h] = m.wrong[h] + 1
                else
                    m.missed[h] = m.missed[h] + 1
                end
            elseif cr > 0 then
                m.falseWounds[cr] = m.falseWounds[cr] + 1
                if c.verdict[i] ~= 2 then
                    m.falseNet[cr] = m.falseNet[cr] + 1
                end
            end
            local v = c.verdict[i]
            if v > 0 then -- judged: another source's outcome (a false credit) or our own swing's (credited right)
                local ours = s.src[i] == 1 and h > 0
                m.judged = m.judged + 1
                if not ours then
                    m.falseJudged, m.caught = m.falseJudged + 1, m.caught + (v == 2 and 1 or 0)
                elseif v == 2 and cr == h and c.crAt[i] == s.swingT[i] then
                    m.falseRetracted = m.falseRetracted + 1
                end
            end
        end
        if c.crHand[i] > 0 and not c.crTok[i] then
            m.nonTarget = m.nonTarget + 1
        end
    end
    -- the avoids credited to our swings (SWING_MISSED rows), each by the outcome its swing took: that swing's own
    -- avoid (right), another swing's of ours (wrong), or another source's or an unexplained one (a false credit)
    for k = 1, math.min(c.rows.missed, #c.missHand) do
        local h, at = c.missHand[k], c.missAt[k]
        if inside(at) then
            local i = 0
            for a = c.nAv, 1, -1 do
                if c.avHand[a] == h and c.avAt[a] == at then
                    i = c.avIdx[a]
                    break
                end
            end
            if i > 0 and s.src[i] == 1 then
                if s.hand[i] == h and s.swingT[i] == at then
                    m.avoidRight = m.avoidRight + 1
                else
                    m.avoidWrong = m.avoidWrong + 1
                end
            else
                m.falseAvoids[h] = m.falseAvoids[h] + 1
            end
        end
    end
    local HIT = { WOUND = true, BLOCK = true, DODGE = true, PARRY = true, MISS = true, HEAL = true }
    for i = 1, s.n do -- hits on us (harness design §4.3): credited to the right attacker, and every one staged
        if s.ev[i] == "UNIT_COMBAT" and s.a1[i] == "player" then
            m.hitsFed = m.hitsFed + (HIT[s.a2[i]] and 1 or 0)
            if s.src[i] == 2 and s.a2[i] ~= "HEAL" then
                m.onusAll = m.onusAll + 1
                if c.onus[i] ~= "" then
                    m.onusCredited = m.onusCredited + 1
                    if W and c.onus[i] == W.ents[s.actor[i]].guid then
                        m.onusRight = m.onusRight + 1
                    end
                end
            end
        end
    end
    m.hitsStaged = m.hitsStaged + c.hits
    m.late = m.late + c.nLate
    for k = 1, c.nLate do -- a rescue was ours when it paid our swing whose wound landed and went uncredited
        m.rescued = m.rescued + 1
        for i = 1, s.n do
            if s.src[i] == 1 and s.hand[i] == c.lateHand[k] and s.swingT[i] == c.lateAt[k] and s.a1[i] == "target" then
                if s.a2[i] == "WOUND" and s.a4[i] > 0 and c.crHand[i] == 0 then
                    m.rescuedOurs = m.rescuedOurs + 1
                end
                break
            end
        end
    end
    if W then
        for w = 1, c.nWin - 1 do
            local a, b = c.winT[w], c.winT[w + 1]
            local err = (c.win[w + 1] - c.win[w]) - (truthAt(W, b) - truthAt(W, a))
            m.windows = m.windows + 1
            m.errSum = m.errSum + err
            if math.abs(err) > m.errMax then
                m.errMax = math.abs(err)
            end
            if err >= step then
                m.over = m.over + 1
            end
            m.loOver = m.loOver + c.loOver[w]
            m.estOver, m.danger = m.estOver + c.estOver[w], m.danger + c.danger[w]
        end
    end
    m.noDst, m.order = m.noDst + c.rows.noDst, m.order + c.rows.order
    return m
end

-- Our true value of power type `pt` as a function of time, for times asked in increasing order: the swing-paid type's
-- from `ev.power`, another's from `ev.resCur` (its start value before any event); and the time of its last change.
local function truthOf(W, pt)
    local us, truth, i = W.ents[1], W.truth, 0
    local v, changed = (pt == us.pt) and 0 or (us.res0[pt] or 0), -math.huge
    return function(t)
        while truth[i + 1] and truth[i + 1].t <= t do
            i = i + 1
            local ev = truth[i]
            local x = (pt == us.pt and ev.power) or (ev.pt == pt and ev.resCur) or nil
            if x and x ~= v then
                v, changed = x, ev.t
            end
        end
        return v, changed
    end
end
M.truthOf = truthOf

--- One tracked power type's belief against the truth (drive's `c.trk[pt]`, GCD kinds design §2.4), from `o.after`
--- seconds on, up to the world's end (W.t: the drive ticks on past it) and at times `o.keep(t)` accepts: { n, meanAbs, maxAbs, windows (10 s), over (windows with a tick whose
--- lo is above the truth by more than `overBar`), overMax (the largest lo above the truth), exact (the share of ticks,
--- `o.settle` (0.25) s or more after the truth's last change and our last cast, whose est equals the truth) }.
function M.power(c, W, pt, overBar, o)
    o = o or {}
    local r, at = c.trk[pt], truthOf(W, pt)
    local after, settle = o.after or 0, o.settle or 0.25
    local casts, ci = {}, 1
    for _, ev in ipairs(W.truth) do
        if ev.kind == "cast" and ev.src == W.ents[1] then
            casts[#casts + 1] = ev.t
        end
    end
    local out = { n = 0, meanAbs = 0, maxAbs = 0, windows = 0, over = 0, overMax = 0, exact = 1, settled = 0 }
    local sum, hits, win, winOver = 0, 0, nil, false
    local function close()
        if win then
            out.windows = out.windows + 1
            out.over = out.over + (winOver and 1 or 0)
        end
    end
    for k = 1, r.n do
        local t = r.t[k]
        local v, changed = at(t)
        while casts[ci + 1] and casts[ci + 1] <= t do
            ci = ci + 1
        end
        if t >= after and t <= W.t and (o.keep == nil or o.keep(t)) then
            local err = r.est[k] - v
            out.n, sum = out.n + 1, sum + math.abs(err)
            out.maxAbs = math.max(out.maxAbs, math.abs(err))
            local w = math.floor(t / 10)
            if w ~= win then
                close()
                win, winOver = w, false
            end
            local over = r.lo[k] - v
            out.overMax = math.max(out.overMax, over)
            winOver = winOver or over > overBar
            local lastCast = casts[ci] and casts[ci] <= t and casts[ci] or -math.huge
            if t - changed >= settle and t - lastCast >= settle then
                out.settled = out.settled + 1
                hits = hits + (r.est[k] == v and 1 or 0)
            end
        end
    end
    close()
    out.meanAbs = out.n > 0 and sum / out.n or 0
    out.exact = out.settled > 0 and hits / out.settled or 1
    return out
end

--- Each GCD of ours (W's casts with `gcd`) against the belief's (drive's `c.gcdS`/`c.gcdE`): { n (true), seen (a
--- believed one at its start, within 0.01 s), owned, ownerless (of those seen, by the opener at the first tick),
--- errMax (|believed end - true end|), extra (believed GCDs no press opened) }.
function M.gcd(c, W)
    local out = { n = 0, seen = 0, owned = 0, ownerless = 0, errMax = 0, extra = 0 }
    local starts, ends = {}, {}
    for _, ev in ipairs(W.truth) do
        if ev.kind == "cast" and ev.src == W.ents[1] and ev.gcd then
            out.n = out.n + 1
            starts[out.n], ends[out.n] = ev.t, ev.t + ev.gcd
        end
    end
    local j = 1
    for k = 1, c.gcdN do
        local gs = c.gcdS[k]
        while starts[j] and starts[j] < gs - 0.01 do
            j = j + 1
        end
        if starts[j] and math.abs(starts[j] - gs) <= 0.01 then
            out.seen = out.seen + 1
            out.errMax = math.max(out.errMax, math.abs(c.gcdE[k] - ends[j]))
            if c.gcdOwned[k] == 1 then
                out.owned = out.owned + 1
            else
                out.ownerless = out.ownerless + 1
            end
            j = j + 1
        else
            out.extra = out.extra + 1
        end
    end
    return out
end

--- Our white wounds on the target at times `keep(t)` accepts, and how many Rows.lua scored on timing alone (drive's
--- `c.unk`: the form differs from the damage cache's): n, unknown.
function M.unknown(c, s, keep)
    local n, u = 0, 0
    for i = 1, s.n do
        if s.ev[i] == "UNIT_COMBAT" and s.src[i] == 1 and s.hand[i] > 0 and s.a1[i] == "target" and s.a4[i] > 0 then
            if keep == nil or keep(s.t[i]) then
                n, u = n + 1, u + c.unk[i]
            end
        end
    end
    return n, u
end

--- The crits staged (c = 3, drive's `c.crit3`) among our credited white wounds: crits (credited and CRITICAL), staged
--- (of those, with a c = 3), false (a c = 3 on a credited non-crit).
function M.crits(c, s)
    local crits, staged, false3 = 0, 0, 0
    for i = 1, s.n do
        if s.ev[i] == "UNIT_COMBAT" and c.crHand[i] > 0 then
            if s.a3[i] == "CRITICAL" then
                crits, staged = crits + 1, staged + (c.crit3[i] > 0 and 1 or 0)
            elseif c.crit3[i] > 0 then
                false3 = false3 + 1
            end
        end
    end
    return crits, staged, false3
end

--- The share of hand h's own hits credited to the right swing.
function M.rate(m, h)
    return m.own[h] > 0 and m.right[h] / m.own[h] or 1
end

--- False credits per 100 of our swings: the wounds as credited (`m.falseWounds`, the default), net of the oracle's
--- retractions (`m.falseNet`) or the avoids (`m.falseAvoids`).
function M.falsePer100(m, f)
    f = f or m.falseWounds
    return m.swings > 0 and 100 * (f[1] + f[2]) / m.swings or 0
end

--- Runs `n` fights of scenario `o` (seeds 1..n), each on a fresh VirtualState, and returns their tally (outcomes
--- from `after` seconds on).
function M.fights(o, n, after)
    local scenarios = require("Game.harness.scenarios")
    local drive = require("Game.harness.drive")
    local m = M.new()
    for seed = 1, n do
        local s, W = scenarios.stream(o, seed)
        local c = drive.boot({ max = o.max, oracle = o.oracle })
        drive.run(c, s)
        M.score(m, c, s, W, 9, after)
        drive.restore(c)
    end
    return m
end

--- The oracle's line: judged, false credits judged and caught, own credits retracted, rescues and how many were ours.
function M.oracleLine(m)
    return string.format(
        "judged %d (%.1f a fight), false judged %d caught %d, own retracted %d of %d, rescued %d ours %d, lo over %d/%d",
        m.judged,
        m.judged / math.max(1, m.fights),
        m.falseJudged,
        m.caught,
        m.falseRetracted,
        m.right[1] + m.right[2],
        m.rescued,
        m.rescuedOurs,
        m.loOver,
        m.windows
    ) .. string.format(", est over %d, danger %d", m.estOver, m.danger)
end

--- Hits on us: precision (credited to the right attacker / credited), coverage (credited / all), staged and fed.
function M.onusLine(m)
    return string.format(
        "hits on us %d: credited %d, right %d (precision %.3f, coverage %.3f); PlayerHit staged %d of %d fed",
        m.onusAll,
        m.onusCredited,
        m.onusRight,
        m.onusCredited > 0 and m.onusRight / m.onusCredited or 1,
        m.onusAll > 0 and m.onusCredited / m.onusAll or 1,
        m.hitsStaged,
        m.hitsFed
    )
end

--- One line for a report (`busted` prints it in a failing assertion's message).
function M.line(m)
    return string.format(
        "fights=%d main %d/%d (wrong %d, missed %d) off %d/%d (wrong %d, missed %d) false wounds %d/%d (%.2f per 100 swings, net %.2f), "
            .. "false avoids %d/%d (%.2f), "
            .. "avoids right %d wrong %d, over %d/%d windows, err mean %.2f max %.1f",
        m.fights,
        m.right[1],
        m.own[1],
        m.wrong[1],
        m.missed[1],
        m.right[2],
        m.own[2],
        m.wrong[2],
        m.missed[2],
        m.falseWounds[1],
        m.falseWounds[2],
        M.falsePer100(m),
        M.falsePer100(m, m.falseNet),
        m.falseAvoids[1],
        m.falseAvoids[2],
        M.falsePer100(m, m.falseAvoids),
        m.avoidRight,
        m.avoidWrong,
        m.over,
        m.windows,
        m.windows > 0 and m.errSum / m.windows or 0,
        m.errMax
    )
end

return M
