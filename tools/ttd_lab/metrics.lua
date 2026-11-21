-- tools/ttd_lab/metrics.lua: per algorithm and scenario class. Every poll while the target lives counts.
-- unknown: share of polls with no answer. Errors on answered polls: abs = |est - true| s, rel = |est - true| /
-- max(true, 2 s) (so the last two seconds count as absolute / 2); "common": only polls every main-lineup algorithm
-- answered (no selection bias). early = first 25% of the stream's targeted life, late = last 25%.
-- Decisions (the consumer's view: unknown reads as very long, so `ttd < X` is false): time_to_die < 4, 8, 15 against
-- the true time to die, fight_remains < 20 against the true end of the fight (the last mob's death; only the target
-- has an estimate, so the target's answer is the fight's). wrong = share of polls on the wrong side; excess flips
-- per minute = flips of a decision within a stream beyond the truth's own flips there.
-- First answer: seconds from the stream's start (unit change) to its first answer; a stream never answered counts
-- its whole polled time and adds to `never`.
local M = {}

M.TTD_X = { 4, 8, 15 }
M.FIGHT_X = 20
M.ND = 4

local log, floor, exp = math.log, math.floor, math.exp

local function hadd(h, x)
    local b = floor(log(1 + x) * 200)
    h[b] = (h[b] or 0) + 1
    h.n = h.n + 1
end

local function hq(h, q)
    if h.n == 0 then
        return nil
    end
    local keys = {}
    for k in pairs(h) do
        if k ~= "n" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local want, acc = q * h.n, 0
    for _, k in ipairs(keys) do
        acc = acc + h[k]
        if acc >= want then
            return exp((k + 0.5) / 200) - 1
        end
    end
end
M.quantile = hq

local HISTS = { "abs", "rel", "absE", "relE", "absL", "relL", "absC", "relC" }

function M.newStats()
    local s = { polls = 0, unknown = 0, wrong = {}, excess = {}, time = 0, delays = {}, never = 0, streams = 0 }
    for _, h in ipairs(HISTS) do
        s[h] = { n = 0 }
    end
    for d = 1, M.ND do
        s.wrong[d], s.excess[d] = 0, 0
    end
    return s
end

local function decide(est, x)
    return est and est < x or false
end

--- Adds one fight: `obs.polls`, `answers[a]` per algorithm (est or false), `stats[a]` to add to, `main` the
--- algorithm indexes of the main lineup (for the common mask).
function M.add(obs, answers, stats, main)
    local P = obs.polls
    local na = #answers
    local cur, first = {}, nil
    local prevD, flips, tflips, prevT = {}, {}, {}, {}
    local answered = {}
    local function closeStream(lastT)
        if not first then
            return
        end
        for a = 1, na do
            local s = stats[a]
            s.streams = s.streams + 1
            s.time = s.time + (lastT - first.t)
            if answered[a] then
                s.delays[#s.delays + 1] = answered[a]
            else
                s.never = s.never + 1
                s.delays[#s.delays + 1] = lastT - first.start
            end
            for d = 1, M.ND do
                s.excess[d] = s.excess[d] + math.max(0, flips[a][d] - tflips[d])
            end
        end
    end
    local lastT
    for i = 1, P.n do
        local sid, t, tru = P.stream[i], P.t[i], P.tru[i]
        if sid ~= cur.sid then
            closeStream(lastT)
            cur.sid, first = sid, { t = t, start = P.start[i] }
            for a = 1, na do
                prevD[a], flips[a], answered[a] = {}, { 0, 0, 0, 0 }, nil
            end
            for d = 1, M.ND do
                tflips[d], prevT[d] = 0, nil
            end
        end
        lastT = t
        local life = P.death[i] - P.start[i]
        local frac = life > 0 and (t - P.start[i]) / life or 1
        local common = true
        for _, a in ipairs(main) do
            if not answers[a][i] then
                common = false
                break
            end
        end
        for d = 1, M.ND do
            local truth = d < M.ND and tru < M.TTD_X[d] or P.fight[i] < M.FIGHT_X
            if prevT[d] ~= nil and prevT[d] ~= truth then
                tflips[d] = tflips[d] + 1
            end
            prevT[d] = truth
        end
        for a = 1, na do
            local s, est = stats[a], answers[a][i]
            s.polls = s.polls + 1
            if est then
                if not answered[a] then
                    answered[a] = t - P.start[i]
                end
                local ae = math.abs(est - tru)
                local re = ae / math.max(tru, 2)
                hadd(s.abs, ae)
                hadd(s.rel, re)
                if frac < 0.25 then
                    hadd(s.absE, ae)
                    hadd(s.relE, re)
                elseif frac >= 0.75 then
                    hadd(s.absL, ae)
                    hadd(s.relL, re)
                end
                if common then
                    hadd(s.absC, ae)
                    hadd(s.relC, re)
                end
            else
                s.unknown = s.unknown + 1
                est = nil
            end
            local pd = prevD[a]
            for d = 1, M.ND do
                local truth, dec
                if d < M.ND then
                    truth, dec = tru < M.TTD_X[d], decide(est, M.TTD_X[d])
                else
                    truth, dec = P.fight[i] < M.FIGHT_X, decide(est, M.FIGHT_X)
                end
                if dec ~= truth then
                    s.wrong[d] = s.wrong[d] + 1
                end
                if pd[d] ~= nil and pd[d] ~= dec then
                    flips[a][d] = flips[a][d] + 1
                end
                pd[d] = dec
            end
        end
    end
    closeStream(lastT)
end

local function sortedQ(list, q)
    if #list == 0 then
        return nil
    end
    local c = {}
    for i, v in ipairs(list) do
        c[i] = v
    end
    table.sort(c)
    return c[math.max(1, math.ceil(q * #c))]
end

--- The summary numbers of one stats record.
function M.summary(s)
    local r = {
        unknown = s.polls > 0 and s.unknown / s.polls or 0,
        absMed = hq(s.abs, 0.5),
        absP90 = hq(s.abs, 0.9),
        relMed = hq(s.rel, 0.5),
        relP90 = hq(s.rel, 0.9),
        relEMed = hq(s.relE, 0.5),
        relEP90 = hq(s.relE, 0.9),
        relLMed = hq(s.relL, 0.5),
        relLP90 = hq(s.relL, 0.9),
        absEMed = hq(s.absE, 0.5),
        absLMed = hq(s.absL, 0.5),
        relCMed = hq(s.relC, 0.5),
        relCP90 = hq(s.relC, 0.9),
        absCMed = hq(s.absC, 0.5),
        delayMed = sortedQ(s.delays, 0.5),
        delayP90 = sortedQ(s.delays, 0.9),
        never = s.streams > 0 and s.never / s.streams or 0,
        wrong = {},
        flips = {},
    }
    local minutes = s.time / 60
    local wsum, fsum = 0, 0
    for d = 1, M.ND do
        r.wrong[d] = s.polls > 0 and s.wrong[d] / s.polls or 0
        r.flips[d] = minutes > 0 and s.excess[d] / minutes or 0
        wsum, fsum = wsum + r.wrong[d], fsum + r.flips[d]
    end
    r.wrongMean, r.flipSum = wsum / M.ND, fsum
    return r
end

--- The mean of several summaries (scenario classes weigh equally overall); nil entries are skipped.
function M.mean(list)
    local out = { wrong = {}, flips = {} }
    local keys = {}
    for k, v in pairs(list[1]) do
        if type(v) == "number" then
            keys[#keys + 1] = k
        end
    end
    for _, k in ipairs(keys) do
        local s, n = 0, 0
        for _, r in ipairs(list) do
            if r[k] then
                s, n = s + r[k], n + 1
            end
        end
        out[k] = n > 0 and s / n or nil
    end
    for d = 1, M.ND do
        local w, f = 0, 0
        for _, r in ipairs(list) do
            w, f = w + r.wrong[d], f + r.flips[d]
        end
        out.wrong[d], out.flips[d] = w / #list, f / #list
    end
    return out
end

-- The combined score: each term over its median across the reference lineup, weighted; lower is better.
M.TERMS = { "unknown", "relMed", "relP90", "wrongMean", "flipSum" }
M.WEIGHTS = { unknown = 1, relMed = 0.5, relP90 = 0.5, wrongMean = 1, flipSum = 1 }

function M.refs(summaries)
    local refs = {}
    for _, term in ipairs(M.TERMS) do
        local v = {}
        for _, r in ipairs(summaries) do
            v[#v + 1] = r[term] or 0
        end
        refs[term] = math.max(sortedQ(v, 0.5) or 1, 1e-3)
    end
    return refs
end

function M.score(r, refs, weights)
    weights = weights or M.WEIGHTS
    local s, w = 0, 0
    for _, term in ipairs(M.TERMS) do
        s, w = s + weights[term] * (r[term] or 10) / refs[term], w + weights[term]
    end
    return s / w
end

return M
