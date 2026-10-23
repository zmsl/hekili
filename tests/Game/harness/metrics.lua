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
        onusAll = 0,
        onusCredited = 0,
        onusRight = 0,
        hitsFed = 0,
        hitsStaged = 0,
        avoidRight = 0,
        avoidWrong = 0,
    }
end

-- Whether a credit of another source's outcome to our swing of hand `h` at `at` (its flag `flag`) puts false rage in
-- the belief: rage is gained at the swing (checkpoint R1), so a wrong row whose swing did land with the same kind of
-- hit pays the right rage. False: that swing was avoided, none of ours was due then, or its kind (crit or not) differs
-- where a crit pays more rage in this world (`critPays[h]`).
local function rageFalse(s, own, h, at, flag, critPays)
    local i = own[h] and own[h][at]
    if not i or s.a2[i] ~= "WOUND" then
        return true
    end
    return critPays[h] and (s.a3[i] == "CRITICAL") ~= (flag == "CRITICAL")
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

-- Whether group g's paying ticket is its own cast's: the anchor is the observed success, up to K10's cast-event jitter
-- (0.05 s, behaviours.ours) after the truth's (our presses are 1.5 s or more apart)
local function anchored(g)
    return g.at >= g.castT - 1e-6 and g.at <= g.castT + 0.05 + 1e-6
end

--- Adds one fight (drive captures `c`, stream `s`, world `W`) to tally `m`: the outcomes from `after` seconds on (default
--- all), and only at times `keep(t)` accepts when given (a section of the fight). `step`: one main-hand step (the
--- overshoot bar, default 9). Returns `m`.
function M.score(m, c, s, W, step, after, keep)
    step, after = step or 9, after or 0
    -- our swings' own outcomes by hand and swing time (the stream index of their target outcome), and whether a crit of
    -- that hand pays more rage than a plain hit in this world (no world: assume it does)
    local own, critPays = { {}, {} }, { not W, not W }
    if W then
        local plain, crit = {}, {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" and ev.src == W.ents[1] and ev.rage and ev.hand then
                local t = ev.flag == "CRITICAL" and crit or plain
                t[ev.hand] = math.max(t[ev.hand] or 0, ev.rage)
            end
        end
        for h = 1, 2 do
            critPays[h] = (crit[h] or 0) > (plain[h] or 0)
        end
    end
    for i = 1, s.n do
        if s.ev[i] == "UNIT_COMBAT" and s.src[i] == 1 and s.hand[i] > 0 and s.a1[i] == "target" then
            own[s.hand[i]][s.swingT[i]] = i
        end
    end
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
            local vh = c.vetoHand[i]
            if vh > 0 then -- a veto: the usability check judged this wound's swing before it was credited
                m.judged = m.judged + 1
                if not (s.src[i] == 1 and h > 0) and rageFalse(s, own, vh, c.vetoAt[i], s.a3[i], critPays) then
                    m.falseJudged, m.caught = m.falseJudged + 1, m.caught + 1
                elseif s.src[i] == 1 and h == vh and s.swingT[i] == c.vetoAt[i] then
                    m.falseRetracted = m.falseRetracted + 1 -- our own swing's wound, denied: an own retraction
                end
            end
            local v = c.verdict[i]
            if v > 0 then -- judged: a rage-false credit, or our own swing's outcome credited right
                local ours = s.src[i] == 1 and h > 0
                m.judged = m.judged + 1
                if not ours and rageFalse(s, own, cr, c.crAt[i], s.a3[i], critPays) then
                    m.falseJudged, m.caught = m.falseJudged + 1, m.caught + (v == 2 and 1 or 0)
                elseif ours and v == 2 and cr == h and c.crAt[i] == s.swingT[i] then
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

--- The oracle's line: judged (vetoes included), rage-false credits judged and caught, own credits retracted.
function M.oracleLine(m)
    return string.format(
        "judged %d (%.1f a fight), false judged %d caught %d, own retracted %d of %d, lo over %d/%d",
        m.judged,
        m.judged / math.max(1, m.fights),
        m.falseJudged,
        m.caught,
        m.falseRetracted,
        m.right[1] + m.right[2],
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

--- A fresh spell-ticket tally (unit-registry spec §6.2).
function M.newTickets()
    return {
        fights = 0,
        own = 0, -- own spell outcomes in the truth (castT > 0) on a registry token
        right = 0, -- paid by their own ticket
        wrong = 0, -- paid by another ticket of ours
        missed = 0, -- paid by nothing
        paid = 0, -- rows that paid a spell ticket
        falsePaid = 0, -- of those, rows that were not that ticket's
        foreignRows = 0,
        foreignPaid = 0,
        staged = 0, -- Crit or Avoided staged for the right cast
        stagedTruth = 0, -- own crits and refused avoids in the truth
        divergent = 0,
        lostEngine = 0, -- FRAME and FLIGHT rows the engine counted lost
        lostTruth = 0, -- own instant and projectile successes with no row in the truth
        outcomes = 0, -- distinct outcomes on registry tokens (any source)
        dispatched = 0, -- rows the registry dispatched
        overflow = 0,
        postClear = 0, -- own white outcomes landing after their target's kill clear (the measured kill shape)
        postClearPaid = 0, -- of those, paid by a swing ticket
        dead = 0, -- tickets the engine closed dead (K11)
        kills = 0, -- kills of our target in the truth (K11)
        gone = 0, -- TargetGone observations (K11)
        ended = 0, -- tickets closed at combat end (K17)
        afterReset = 0, -- rows after the combat end that paid a ticket opened before it (K17: must be 0)
        aoeOther = 0, -- foreign rows the engine marked as our spell's on another GUID (K18)
        errors = 0, -- the engine's event errors
        petRows = 0, -- our pet's outcomes on our target (K14)
        petPaid = 0, -- of those, paid by any ticket of ours (a swing credit or a spell ticket: must stay 0)
        twinDivergent = 0, -- swapped pairs of a different class (K13; the engine's T.divergent sees own pairs only)
        inFlight = 0, -- fights where another source killed our target while a bolt of ours flew (K11)
        inFlightLost = 0, -- of those bolts, the ones closed lost or paid by a row after the death (K11: must be 0)
    }
end

local REG = { target = true, focus = true, softenemy = true, softinteract = true }
local function registry(tok)
    return REG[tok] or tok:match("^nameplate") ~= nil
end

-- Whether hand h's swing at swingT took an avoid provisionally (Rows' T.Provisional, the drive's c.avIdx) and kept it:
-- no wound was credited to that swing after (its SWING_MISSED comes at the window's end, or nothing at combat end,
-- spec §3.6, but the row paid its swing ticket either way).
local function provisional(c, s, h, swingT)
    for j = 1, c.nAv do
        if c.avHand[j] == h and math.abs(c.avAt[j] - swingT) < 1e-6 then
            for i = 1, s.n do
                if c.crHand[i] == h and math.abs(c.crAt[i] - swingT) < 1e-6 then
                    return false
                end
            end
            return true
        end
    end
    return false
end

--- Adds one fight (drive captures `c`, stream `s`, world `W`) to tally `m`: outcomes grouped across their tokens, each
--- group's paying ticket from the drive's captures (spell tickets only: MELEE's are metrics.score's).
function M.tickets(m, c, s, W)
    local X = c.I.Expect
    m.fights = m.fights + 1
    -- unit: each token's last GUID (one outcome is one unit's; a cleared token's late rows are still that unit's)
    local groups, list, unit = {}, {}, {}
    for i = 1, s.n do
        if s.ev[i] == "@guid" and s.a2[i] then
            unit[s.a1[i]] = s.a2[i]
        elseif s.ev[i] == "UNIT_COMBAT" and registry(s.a1[i]) then
            local key = string.format(
                "%s/%s/%.4f/%s/%s/%s/%s/%s/%s",
                tostring(unit[s.a1[i]]),
                tostring(s.hand[i]), -- our twin hands in one ms with one amount (K14) are two outcomes
                s.t[i],
                s.a2[i],
                tostring(s.a4[i]),
                tostring(s.a5[i]),
                tostring(s.castT and s.castT[i] or 0),
                tostring(s.actor and s.actor[i] or 0),
                tostring(s.swingT[i])
            )
            local g = groups[key]
            if not g then
                g = { own = (s.castT and s.castT[i] or 0) > 0, castT = s.castT and s.castT[i] or 0, at = 0, kind = 0 }
                g.t, g.act, g.unit = s.t[i], s.a2[i], unit[s.a1[i]]
                g.crit, g.avoid = s.a3[i] == "CRITICAL", s.a2[i] == "DODGE" or s.a2[i] == "PARRY" or s.a2[i] == "MISS"
                groups[key], list[#list + 1] = g, g
            end
            if s.a1[i] == "target" then
                g.onTarget = true
            end
            if c.payAt[i] > 0 and c.payKind[i] ~= X.MELEE then
                g.at, g.kind, g.staged = c.payAt[i], c.payKind[i], c.staged[i]
            end
        end
    end
    m.outcomes = m.outcomes + #list
    m.dispatched = m.dispatched + c.rowsOut
    -- An own outcome off our target in the same frame as that cast's outcome on it is our AoE's (the engine's aoeOther,
    -- K18): neither own nor foreign, never missed. A pinned cast landing alone after a swap (K5) stays own.
    local onTarget = {}
    for _, g in ipairs(list) do
        if g.own and g.onTarget then
            onTarget[g.t .. "/" .. g.castT] = true
        end
    end
    -- A swapped pair (spec §4.2, K13): our outcome unpaid and another source's on its unit within SAME_FRAME (0.05 s)
    -- paid our cast's ticket. An equal class (act, crit) is the same state either way: ours counts right, theirs is
    -- neither false credit nor leak. A different class is a divergent pair: ours stays missed, theirs false credit.
    -- Only when the tally asks (m.swaps: K13's kinds); on K1-K9 it would raise K2, K4, K5, K7 and K8's crowd cells.
    for _, g in ipairs(m.swaps and list or {}) do
        if g.own and g.at == 0 then
            for _, f in ipairs(list) do
                if
                    not f.own
                    and not f.swapped
                    and f.at > 0
                    and f.unit == g.unit
                    and math.abs(f.t - g.t) <= 0.05
                    and anchored({ at = f.at, castT = g.castT })
                then
                    if f.act == g.act and f.crit == g.crit then
                        f.swapped, g.swapRight, g.staged = true, true, f.staged
                    else
                        m.twinDivergent = m.twinDivergent + 1
                    end
                    break
                end
            end
        end
    end
    for _, g in ipairs(list) do
        local aoe = g.own and not g.onTarget and onTarget[g.t .. "/" .. g.castT]
        if g.own and not aoe then
            m.own = m.own + 1
            if g.swapRight or (g.at > 0 and anchored(g)) then
                m.right = m.right + 1
                if (g.crit or g.avoid) and (g.staged or 0) > 0 then
                    m.staged = m.staged + 1
                end
            elseif g.at > 0 then
                m.wrong = m.wrong + 1
            else
                m.missed = m.missed + 1
            end
            if g.crit or g.avoid then
                m.stagedTruth = m.stagedTruth + 1
            end
        elseif not aoe and not g.swapped then
            m.foreignRows = m.foreignRows + 1
            if g.at > 0 then
                m.foreignPaid = m.foreignPaid + 1
            end
        end
        if g.at > 0 then
            m.paid = m.paid + 1
            if not (g.own and anchored(g)) and not g.swapped then
                m.falsePaid = m.falsePaid + 1
            end
        end
    end
    local T = c.I.Tickets
    m.divergent = m.divergent + T.divergent
    m.lostEngine = m.lostEngine + T.lost[X.FRAME] + T.lost[X.FLIGHT]
    m.overflow = m.overflow + T.closed.overflow
    if W then -- own white outcomes landing 0.1-2 s after their target's kill (after the clear): paid by their swing
        -- Scope (K6 ruling): rows before the next PLAYER_REGEN_ENABLED (the reset at combat end closes every ticket,
        -- spec §2.5 and K17), and not a school-1 MISS a FLIGHT ticket paid (no school gate can refuse it: it counts
        -- under false credit and leak, spec §3.4, not here).
        local seen, spell = {}, {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "kill" and ev.dst == ev.ourTarget then
                local reset = math.huge
                for i = 1, s.n do
                    if s.ev[i] == "PLAYER_REGEN_ENABLED" and s.t[i] > ev.t then
                        reset = s.t[i]
                        break
                    end
                end
                for i = 1, s.n do
                    if
                        s.ev[i] == "UNIT_COMBAT"
                        and s.src[i] == 1
                        and s.hand[i] > 0
                        and s.swingT[i] <= ev.t
                        and s.t[i] > ev.t + 0.1
                        and s.t[i] <= ev.t + 2
                        and s.t[i] < reset
                    then
                        local key = s.t[i] .. "/" .. s.swingT[i]
                        seen[key] = seen[key] or false
                        if
                            c.payKind[i] == X.MELEE
                            or (s.a2[i] ~= "WOUND" and provisional(c, s, s.hand[i], s.swingT[i]))
                        then
                            seen[key] = true
                        elseif s.a2[i] == "MISS" and s.a5[i] == 1 and c.payKind[i] == X.FLIGHT then
                            spell[key] = true
                        end
                    end
                end
            end
        end
        for key, paid in pairs(seen) do
            if not spell[key] then
                m.postClear = m.postClear + 1
                m.postClearPaid = m.postClearPaid + (paid and 1 or 0)
            end
        end
    end
    if W then -- our instant and projectile successes no row of the truth answers
        local rowAt = {}
        for i = 1, s.n do
            if s.castT and s.castT[i] > 0 then
                rowAt[s.castT[i]] = true
            end
        end
        local us, killAt = W.ents[1], {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "kill" then
                killAt[ev.dst] = ev.t
            end
        end
        for _, ev in ipairs(W.truth) do
            local sp = ev.spell
            if ev.kind == "cast" and ev.src == us and (sp == "INSTANT" or sp == "BOLT" or sp == "BOGUS") then
                -- not lost but closed dead (K6): a cast whose target died between its success and the end of its hard
                -- window, H = 30 / 20 + TOL 0.15 (detect.boot's projectile; an instant lands at once, inside it too),
                -- and a cast at a target already dead (the harness keeps pressing at the corpse; no row can come, and
                -- the engine closes its ticket dead: counting it lost made lostDiff 164-249 in K6)
                local k = killAt[ev.dst]
                if not rowAt[ev.t] and not (k and k <= ev.t + 1.65) then
                    m.lostTruth = m.lostTruth + 1
                end
            end
        end
    end
    m.dead, m.ended, m.aoeOther = m.dead + T.closed.dead, m.ended + T.closed.ended, m.aoeOther + T.aoeOther
    m.gone, m.errors = m.gone + c.gone, m.errors + c.I.Events.errors
    if W then
        local regen, us, flew = math.huge, W.ents[1], false
        for _, ev in ipairs(W.truth) do
            if ev.kind == "kill" and ev.dst == ev.ourTarget then
                m.kills = m.kills + 1
                for _, cv in ipairs(W.truth) do -- detect.boot's projectile: W.distance yd at 20 yd/s
                    local d = (W.distance or 20) / 20
                    if
                        cv.kind == "cast"
                        and cv.src == us
                        and cv.spell == "BOLT"
                        and ev.src ~= us
                        and cv.dst == ev.dst
                        and cv.t < ev.t
                        and ev.t <= cv.t + d
                    then
                        flew = true
                        local bad = false
                        for j = 1, c.nLost do
                            bad = bad or math.abs(c.lostAt[j] - cv.t) < 1e-6
                        end
                        for i = 1, s.n do -- a stale row: after the death (a crowd row before it is K4's false credit)
                            bad = bad or (s.t[i] > ev.t and c.payAt[i] > 0 and math.abs(c.payAt[i] - cv.t) < 1e-6)
                        end
                        m.inFlightLost = m.inFlightLost + (bad and 1 or 0)
                    end
                end
            elseif ev.kind == "stop" then
                regen = math.min(regen, ev.t)
            end
        end
        m.inFlight = m.inFlight + (flew and 1 or 0)
        local pet = 0
        for j, e in ipairs(W.ents) do
            pet = e.ourPet and j or pet
        end
        for i = 1, s.n do -- K14: our pet's rows stay foreign (counted once, on the target token)
            if pet > 0 and s.ev[i] == "UNIT_COMBAT" and s.actor[i] == pet and registry(s.a1[i]) then
                m.petRows = m.petRows + (s.a1[i] == "target" and 1 or 0)
                m.petPaid = m.petPaid + ((c.payAt[i] > 0 or c.crHand[i] > 0) and 1 or 0)
            end
        end
        for i = 1, s.n do -- K17: nothing after the combat end pays a ticket opened before it
            if s.t[i] > regen and c.payAt[i] > 0 and c.payAt[i] < regen then
                m.afterReset = m.afterReset + 1
            end
        end
    end
    return m
end

function M.recall(m)
    return m.own > 0 and m.right / m.own or 1
end
function M.false100(m)
    return m.paid > 0 and 100 * m.falsePaid / m.paid or 0
end
function M.leak100(m)
    return m.foreignRows > 0 and 100 * m.foreignPaid / m.foreignRows or 0
end
function M.staged(m)
    return m.stagedTruth > 0 and m.staged / m.stagedTruth or 1
end
function M.divergent100(m)
    return m.own > 0 and 100 * m.divergent / m.own or 0
end
--- Swapped pairs of a different class per 100 own outcomes (the harness's count, spec §4.2).
function M.twinDivergent100(m)
    return m.own > 0 and 100 * m.twinDivergent / m.own or 0
end

--- One line for a detection cell.
function M.ticketLine(m)
    return string.format(
        "fights=%d own=%d recall=%.3f (wrong %d, missed %d) false/100=%.2f leak/100=%.2f staged=%.3f divergent/100=%.2f "
            .. "lost engine=%d truth=%d outcomes=%d dispatched=%d residual=%d overflow=%d postClear=%d/%d",
        m.fights,
        m.own,
        M.recall(m),
        m.wrong,
        m.missed,
        M.false100(m),
        M.leak100(m),
        M.staged(m),
        M.divergent100(m),
        m.lostEngine,
        m.lostTruth,
        m.outcomes,
        m.dispatched,
        m.outcomes - m.dispatched,
        m.overflow,
        m.postClearPaid,
        m.postClear
    )
end

return M
