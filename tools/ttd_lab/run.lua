-- tools/ttd_lab/run.lua: the TTD lab. From the repo root: lua5.1 tools/ttd_lab/run.lua
-- [main|sweep|holdout|run2|tune|drops|run3|run3old|test|all] [--scale x] [--round n] (sweep round, default the last)
-- [--set A|B|C] (seed set: holdout defaults to B, the others to A) [--list name] (tune grids; run3: learn). Prints
-- markdown tables (tools/ttd_lab/README.md explains them).
package.path = "tools/ttd_lab/?.lua;" .. package.path

local S, O, Real = require("scenarios"), require("observe"), require("real")
local B, E, M = require("baselines"), require("estimator"), require("metrics")

local mode, scale, sweepRound, holdSet, tuneList = "main", 1, nil, nil, nil
do
    local i = 1
    while arg[i] do
        if arg[i] == "--scale" then
            scale, i = tonumber(arg[i + 1]), i + 1
        elseif arg[i] == "--set" then
            holdSet, i = arg[i + 1], i + 1
        elseif arg[i] == "--round" then
            sweepRound, i = tonumber(arg[i + 1]), i + 1
        elseif arg[i] == "--list" then
            tuneList, i = arg[i + 1], i + 1
        else
            mode = arg[i]
        end
        i = i + 1
    end
end

-- Fights per class (seed set A tunes, set B holds out; the real traces are the same logs, observed with other seeds).
local COUNTS = {
    trash = 80,
    pack = 50,
    mixed = 50,
    elite = 50,
    boss = 12,
    burst = 60,
    dot = 50,
    execute = 40,
    stall = 40,
    heal = 40,
    phase = 25,
    damaged = 50,
}
local SEED_BASE = { A = 1000, B = 900000, C = 5000000 }

-- Run 2 classes (scenarios.lua S.RUN2): fights per class and a seed offset per class (run 1 offsets the seed by the
-- class name's length). The eight execute classes share one offset: the same fights, only threshold and multiplier
-- differ.
local SEED_OFF = {}
for i, c in ipairs(S.RUN2) do
    COUNTS[c] = c:find("boss") and 40 or 50
    SEED_OFF[c] = c:find("^ex%d") and 100 or 100 + i
end

-- Run 1's winner, pinned: the "before" of run 2 (the estimator's defaults moved on).
local PREV = { detect = 0, execAhead = false, execLearn = 0 }

-- `hints` (run 2): rate = "perfect" (the lust as it starts, its true end), "late" (the caller sees it 0.5-1 s late:
-- startT and endT are the call time and call time + 40 s), "wrong" (no real lust is passed; a phantom x1.3 for 40 s
-- 5 s after the fight's first unit); exec = "perfect" (the fight's true threshold and multiplier), "fixed" (the
-- true threshold, x1.6 whatever the group does), "always" (20% x2 declared on every fight, execute or not), "learn"
-- (the true threshold, the factor learned: it starts at 1 and each fight starts from the factor the previous fight
-- of its class ended with, as a session would; needs `execLearn`), "learn20" (the same with 20% on every fight),
-- "learnAll" (20% on every fight, one session across every class in run order). Sessions start empty per runSet.
local function est(params, hints)
    local p = { spread = false }
    for k, v in pairs(params or {}) do
        p[k] = v
    end
    hints = hints or {}
    local key = {} -- this algorithm's sessions in a run: obs.session[key][class or "all"] = the learned factor
    return function(obs)
        local e = E.New(p)
        local x = obs and obs.execute
        local learnPct = hints.exec == "learn" and x and x.pct
            or (hints.exec == "learn20" or hints.exec == "learnAll") and 20
        local session, slot
        if learnPct then
            session = obs.session[key] or {}
            obs.session[key], slot = session, hints.exec == "learnAll" and "all" or obs.class
        end
        if hints.exec == "perfect" and x then
            e:Hint("execute", x.mult, x.pct)
        elseif hints.exec == "fixed" and x then
            e:Hint("execute", 1.6, x.pct)
        elseif hints.exec == "always" then
            e:Hint("execute", 2, 20)
        elseif learnPct then
            e:Hint("execute", session[slot] or 1, learnPct)
        end
        local pendAt, pendMult, firstT, phantom = nil, nil, nil, false
        local function due(now)
            if pendAt and now >= pendAt then
                e:Hint("rate", pendMult, pendAt, pendAt + 40)
                pendAt = nil
            end
        end
        return {
            e = e,
            restart = function(_, t)
                due(t)
                firstT = firstT or t
                e:Restart()
            end,
            band = function(_, t, lo, hi)
                due(t)
                e:Band(t, lo, hi)
            end,
            get = function(_, now)
                due(now)
                if hints.rate == "wrong" and not phantom and firstT and now >= firstT + 5 then
                    phantom = true
                    e:Hint("rate", 1.3, now, now + 40)
                end
                if learnPct then
                    session[slot] = e:ExecuteFactor()
                end
                return (e:Get(now))
            end,
            lust = function(_, t, mult, endT)
                if hints.rate == "perfect" then
                    e:Hint("rate", mult, t, endT)
                elseif hints.rate == "late" then
                    pendAt, pendMult = t + 0.5 + 0.5 * ((#obs.k * 0.6180339) % 1), mult -- a fixed 0.5-1 s per fight
                end
            end,
        }
    end
end

local function with(...)
    local p = {}
    for _, t in ipairs({ ... }) do
        for k, v in pairs(t) do
            p[k] = v
        end
    end
    return p
end

-- The research note's recommendation as written (section 4), where it differs from the estimator's defaults (the
-- lab's winner).
local RESEARCH =
    with(PREV, { censor = 1, anchorBelow = false, priorEmpty = false, holdStall = false, shrink = 2, window = 18 })

local function base(cls, params)
    return function()
        return cls.new(params)
    end
end

local function hyst(cls)
    return function()
        return B.Hyst.new(cls.new())
    end
end

local MAIN = {
    { "Midpoints (TimeToDie default)", base(B.Midpoints) },
    { "LeastSquares (TimeToDie)", base(B.LeastSquares) },
    { "WeightedLS halving (TimeToDie)", base(B.WeightedLS) },
    { "HeroLib-style OLS 10.4 s", base(B.HeroLib) },
    { "Hekili-retail mean of rates", base(B.Hekili) },
    { "SimC-style cumulative", base(B.Cumulative) },
    { "Ring8 (old plan)", base(B.Ring8) },
    { "Research recommendation (as written)", est(RESEARCH) },
    { "Run 1 winner (pinned)", est(PREV) },
}

-- Answers 30 s once any band is known: the unknown floor (the prime) for reference.
local Floor = {}
Floor.__index = Floor
function Floor.new()
    return setmetatable({}, Floor)
end
function Floor:restart()
    self.known = false
end
function Floor:band()
    self.known = true
end
function Floor:get()
    return self.known and 30 or nil
end

local ABLATION = {
    { "Unknown floor (constant once a band is known)", base(Floor) },
    { "Cumulative + deadband", hyst(B.Cumulative) },
    { "HeroLib + deadband", hyst(B.HeroLib) },
    { "Winner, no deadband", est(with(PREV, { hystAbs = 0 })) },
    { "Winner + censoring (research rule)", est(with(PREV, { censor = 1 })) },
    { "Winner, no full anchor", est(with(PREV, { anchorFull = false })) },
    { "Winner, no below-full anchor", est(with(PREV, { anchorBelow = false })) },
    { "Winner, no carried prior", est(with(PREV, { prior = false })) },
    { "Winner, carried prior only after a crossing", est(with(PREV, { priorEmpty = false })) },
    { "Winner, no stall hold", est(with(PREV, { holdStall = false })) },
    { "Winner, K=2 (research shrink)", est(with(PREV, { shrink = 2 })) },
    { "Winner, seedWeight 1 (own anchor mixed with a carried slope)", est(with(PREV, { seedWeight = 1 })) },
    { "Winner, seedWeight 2", est(with(PREV, { seedWeight = 2 })) },
    { "Winner, seedWeight 4", est(with(PREV, { seedWeight = 4 })) },
}

-- The sweep's leaders (rounds 3-4), run again on the held-out seeds; the last one is the winner.
local TUNED = { censor = 0, anchorBelow = true, priorEmpty = true }
local function tuned(change)
    return est(with(RESEARCH, TUNED, change or {}))
end
local CANDIDATES = {
    { "Tuned (censor 0, anchorBelow, priorEmpty)", tuned() },
    { "Tuned + K=0.5", tuned({ shrink = 0.5 }) },
    { "Tuned + K=0", tuned({ shrink = 0 }) },
    { "Tuned + deadband 3s/0.3", tuned({ hystAbs = 3, hystRel = 0.3 }) },
    { "Tuned + K=0.5 + deadband 2s/0.2", tuned({ shrink = 0.5, hystAbs = 2, hystRel = 0.2 }) },
    { "Tuned + K=0 + window 30", tuned({ shrink = 0, window = 30 }) },
    { "Tuned + K=0 + deadband 2s/0.2", tuned({ shrink = 0, hystAbs = 2, hystRel = 0.2 }) },
    { "Tuned + K=0 + window 30 + holdStall", tuned({ shrink = 0, window = 30, holdStall = true }) },
}

-- One-at-a-time sweeps around a base (round 1: the research defaults; each later round: the previous round's best).
local ROUNDS = {
    { name = "round 1, base = research recommendation", base = RESEARCH },
    { name = "round 2, base = censor 0", base = with(RESEARCH, { censor = 0 }) },
    {
        name = "round 3, base = censor 0, anchorBelow, priorEmpty",
        base = with(RESEARCH, { censor = 0, anchorBelow = true, priorEmpty = true }),
    },
    {
        name = "round 4, base = censor 0, anchorBelow, priorEmpty, K 0",
        base = with(RESEARCH, { censor = 0, anchorBelow = true, priorEmpty = true, shrink = 0 }),
    },
    { name = "round 5, base = the run 1 winner", base = PREV },
}

local function sweepList(baseP)
    local list = {}
    local function add(name, change)
        local p = {}
        for k, v in pairs(baseP) do
            p[k] = v
        end
        for k, v in pairs(change) do
            p[k] = v
        end
        list[#list + 1] = { name, est(p), params = p }
    end
    add("base", {})
    add("anchorBelow on", { anchorBelow = true })
    add("holdStall on", { holdStall = true })
    add("holdStall off", { holdStall = false })
    for _, h in ipairs({ 2, 3, 4, 8, 10, 15 }) do
        add("H=" .. h .. " win=3H", { halfLife = h, window = 3 * h })
    end
    for _, w in ipairs({ 8, 12, 30, 60 }) do
        add("win=" .. w, { window = w })
    end
    for _, k in ipairs({ 0, 0.5, 1, 4, 8, 16 }) do
        add("K=" .. k, { shrink = k })
    end
    for _, x in ipairs({ { 0.5, 0.06 }, { 2, 0.2 }, { 3, 0.3 } }) do
        add("deadband " .. x[1] .. "s/" .. x[2], { hystAbs = x[1], hystRel = x[2] })
    end
    for _, m in ipairs({ 1, 3, 4 }) do
        add("minSpan=" .. m, { minSpan = m })
    end
    for _, f in ipairs({ 2, 5 }) do
        add("fitSpan=" .. f, { fitSpan = f })
    end
    add("priorEmpty on", { priorEmpty = true })
    add("priorTime=4", { priorTime = 4 })
    add("priorTime=15", { priorTime = 15 })
    add("heal>=2", { healReset = 2 })
    add("heal>=5", { healReset = 5 })
    add("stall 3s/x4", { stallGap = 3, stallMult = 4 })
    add("stall 8s/x8", { stallGap = 8, stallMult = 8 })
    for _, c in ipairs({ 0, 2, 3, 5 }) do
        add("censor=" .. c, { censor = c })
    end
    add("floor=0", { floor = 0 })
    add("clamp 0.5-2", { clampLo = 0.5, clampHi = 2 })
    list[#list + 1] = { "Midpoints + deadband", hyst(B.Midpoints) }
    return list
end

local function runSet(set, algos, classes)
    classes = classes or S.CLASSES
    local main = {}
    for a, spec in ipairs(algos) do
        if spec.main then
            main[#main + 1] = a
        end
    end
    local stats, sessions = {}, {} -- sessions: per algorithm, the learned execute factors (est() "learn" hints)
    for _, c in ipairs(classes) do
        stats[c] = {}
        for a = 1, #algos do
            stats[c][a] = M.newStats()
        end
    end
    local function one(class, fight, oseed)
        local obs = O.build(fight, oseed)
        obs.class, obs.session = class, sessions
        local answers = {}
        for a, spec in ipairs(algos) do
            answers[a] = O.run(obs, spec[2](obs), {})
        end
        M.add(obs, answers, stats[class], main)
    end
    local base = SEED_BASE[set]
    for _, c in ipairs(classes) do
        if c ~= "real" then
            for i = 1, math.max(1, math.floor(COUNTS[c] * scale + 0.5)) do
                local seed = base + i * 7919 + (SEED_OFF[c] or #c) * 104729
                one(c, S.build(c, seed), seed + 1)
            end
        end
    end
    local logs = stats.real and Real.logs() or {}
    for li, name in ipairs(logs) do
        if (li - 1) % math.max(1, math.floor(1 / scale + 0.5)) == 0 then
            local ts, as = Real.hits(name)
            for di, d in ipairs(Real.DEATHS) do
                one("real", Real.fight(ts, as, d), base + li * 31 + di)
            end
        end
    end
    local result = { algos = algos, class = {}, overall = {}, classes = classes }
    for a = 1, #algos do
        local per = {}
        for _, c in ipairs(classes) do
            local r = M.summary(stats[c][a])
            result.class[c] = result.class[c] or {}
            result.class[c][a] = r
            per[#per + 1] = r
        end
        result.overall[a] = M.mean(per)
    end
    return result
end

local function f(x, d)
    if x == nil then
        return "-"
    end
    return string.format("%." .. (d or 2) .. "f", x)
end

local function pct(x)
    return x and string.format("%.1f%%", 100 * x) or "-"
end

local function scoreAll(res, refsFrom)
    local refs = M.refs(refsFrom or res.mainSummaries)
    local scores = {}
    for a = 1, #res.algos do
        scores[a] = M.score(res.overall[a], refs)
    end
    return scores, refs
end

local function mainSummaries(res)
    local list = {}
    for a, spec in ipairs(res.algos) do
        if spec.main then
            list[#list + 1] = res.overall[a]
        end
    end
    res.mainSummaries = list
    return list
end

local function ranking(res, title, scores)
    local order = {}
    for a = 1, #res.algos do
        order[a] = a
    end
    table.sort(order, function(x, y)
        return scores[x] < scores[y]
    end)
    print("\n### " .. title .. "\n")
    print(
        "| # | algorithm | score | unknown | rel med | rel p90 | abs med s | wrong (mean of 4) | excess flips/min | first answer med/p90 s | never |"
    )
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for i, a in ipairs(order) do
        local r = res.overall[a]
        print(
            string.format(
                "| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s / %s | %s |",
                i,
                res.algos[a][1],
                f(scores[a], 3),
                pct(r.unknown),
                f(r.relMed),
                f(r.relP90),
                f(r.absMed, 1),
                pct(r.wrongMean),
                f(r.flipSum),
                f(r.delayMed),
                f(r.delayP90),
                pct(r.never)
            )
        )
    end
    return order
end

local function detail(res, order)
    print("\n### Overall detail (class means)\n")
    print(
        "| algorithm | rel med early | rel p90 early | rel med late | rel p90 late | abs med early s | abs med late s | common rel med | common rel p90 | common abs med s |"
    )
    print("|---|---|---|---|---|---|---|---|---|---|")
    for _, a in ipairs(order) do
        local r = res.overall[a]
        print(
            string.format(
                "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
                res.algos[a][1],
                f(r.relEMed),
                f(r.relEP90),
                f(r.relLMed),
                f(r.relLP90),
                f(r.absEMed, 1),
                f(r.absLMed, 1),
                f(r.relCMed),
                f(r.relCP90),
                f(r.absCMed, 1)
            )
        )
    end
    print("\n### Decisions (wrong side % / excess flips per min)\n")
    print("| algorithm | ttd<4 | ttd<8 | ttd<15 | fight_remains<20 |")
    print("|---|---|---|---|---|")
    for _, a in ipairs(order) do
        local r = res.overall[a]
        local cells = {}
        for d = 1, M.ND do
            cells[d] = pct(r.wrong[d]) .. " / " .. f(r.flips[d])
        end
        print("| " .. res.algos[a][1] .. " | " .. table.concat(cells, " | ") .. " |")
    end
end

local function perClass(res, order, key, title, fmt)
    print("\n### " .. title .. " per class\n")
    local head = { "| algorithm" }
    local sep = { "|---" }
    for _, c in ipairs(res.classes) do
        head[#head + 1] = c
        sep[#sep + 1] = "---"
    end
    print(table.concat(head, " | ") .. " |")
    print(table.concat(sep, "|") .. "|")
    for _, a in ipairs(order) do
        local cells = { "| " .. res.algos[a][1] }
        for _, c in ipairs(res.classes) do
            cells[#cells + 1] = fmt(res.class[c][a][key])
        end
        print(table.concat(cells, " | ") .. " |")
    end
end

-- Weight robustness: each weight times a log-uniform factor in [1/2, 2], 2000 draws (a fixed generator).
local function robustness(res, refs, label)
    local rng = require("rng").new(4242)
    local n = #res.algos
    local first, rankSum, top5 = {}, {}, {}
    for a = 1, n do
        first[a], rankSum[a], top5[a] = 0, 0, 0
    end
    local draws = 2000
    for _ = 1, draws do
        local w = {}
        for _, term in ipairs(M.TERMS) do
            w[term] = M.WEIGHTS[term] * 2 ^ rng:uni(-1, 1)
        end
        local sc, order = {}, {}
        for a = 1, n do
            sc[a], order[a] = M.score(res.overall[a], refs, w), a
        end
        table.sort(order, function(x, y)
            return sc[x] < sc[y]
        end)
        for rank, a in ipairs(order) do
            rankSum[a] = rankSum[a] + rank
            if rank == 1 then
                first[a] = first[a] + 1
            end
            if rank <= 5 then
                top5[a] = top5[a] + 1
            end
        end
    end
    local order = {}
    for a = 1, n do
        order[a] = a
    end
    table.sort(order, function(x, y)
        return rankSum[x] < rankSum[y]
    end)
    print("\n### Weight robustness" .. (label or "") .. " (each weight x 2^U(-1,1), 2000 draws)\n")
    print("| algorithm | mean rank | ranked 1st | in top 5 |")
    print("|---|---|---|---|")
    for i, a in ipairs(order) do
        if i <= 12 then
            print(
                string.format(
                    "| %s | %.2f | %s | %s |",
                    res.algos[a][1],
                    rankSum[a] / draws,
                    pct(first[a] / draws),
                    pct(top5[a] / draws)
                )
            )
        end
    end
end

local function lineup(extra)
    local algos = {}
    for _, spec in ipairs(MAIN) do
        algos[#algos + 1] = { spec[1], spec[2], main = true }
    end
    for _, spec in ipairs(extra or {}) do
        algos[#algos + 1] = { spec[1], spec[2], params = spec.params, short = spec.short }
    end
    return algos
end

local function report(res, title)
    mainSummaries(res)
    local scores, refs = scoreAll(res)
    local order = ranking(res, title, scores)
    return order, scores, refs
end

local function header()
    local w = {}
    for _, term in ipairs(M.TERMS) do
        w[#w + 1] = term .. " " .. M.WEIGHTS[term]
    end
    print(
        "Score = weighted mean of (term / median of the main lineup's term); weights: "
            .. table.concat(w, ", ")
            .. ". Lower is better. scale="
            .. scale
    )
end

local modes = {}

function modes.test()
    dofile("tools/ttd_lab/estimator_test.lua")
end

-- Run 2's default and its hints on the run 1 classes (main and holdout tables).
local RUN2_ON_OLD = {
    { "Run 2 default (estimator defaults)", est() },
    { "Run 2 default + rate hint (perfect)", est({}, { rate = "perfect" }) },
    { "Run 2 default + rate hint (wrong, phantom)", est({}, { rate = "wrong" }) },
    { "Run 2 default + execute learned (true threshold)", est({}, { exec = "learn" }) },
    { "Run 2 default + execute learned, 20% always (one session)", est({}, { exec = "learnAll" }) },
    {
        "Run 2 default + rate hint + execute learned 20% (one session)",
        est({}, { rate = "perfect", exec = "learnAll" }),
    },
}

local function extras()
    local extra = {}
    for _, list in ipairs({ ABLATION, CANDIDATES, RUN2_ON_OLD }) do
        for _, spec in ipairs(list) do
            extra[#extra + 1] = spec
        end
    end
    return extra
end

function modes.main()
    print("## Main lineup, ablations and candidates (seed set A)\n")
    header()
    local res = runSet("A", lineup(extras()))
    local order, _, refs = report(res, "Ranking, overall (class means)")
    detail(res, order)
    perClass(res, order, "unknown", "Unknown share", pct)
    perClass(res, order, "relMed", "Relative error median", f)
    perClass(res, order, "relP90", "Relative error p90", f)
    perClass(res, order, "relEMed", "Relative error median, early (first 25%)", f)
    perClass(res, order, "relEP90", "Relative error p90, early (first 25%)", f)
    perClass(res, order, "relLMed", "Relative error median, late (last 25%)", f)
    perClass(res, order, "relLP90", "Relative error p90, late (last 25%)", f)
    perClass(res, order, "absMed", "Absolute error median s", f)
    perClass(res, order, "absP90", "Absolute error p90 s", f)
    perClass(res, order, "absEMed", "Absolute error median s, early", f)
    perClass(res, order, "absLMed", "Absolute error median s, late", f)
    perClass(res, order, "wrongMean", "Wrong side (mean of 4 decisions)", pct)
    perClass(res, order, "flipSum", "Excess flips per minute (sum of 4 decisions)", f)
    perClass(res, order, "delayMed", "First answer median s", f)
    robustness(res, refs)
    local sub = { algos = {}, overall = {} }
    for a, spec in ipairs(res.algos) do
        if spec.main then
            sub.algos[#sub.algos + 1], sub.overall[#sub.overall + 1] = spec, res.overall[a]
        end
    end
    robustness(sub, refs, ", main lineup only")
end

function modes.sweep()
    local round = ROUNDS[sweepRound or #ROUNDS]
    print("## Parameter sweep, " .. round.name .. " (seed set A; one change at a time)\n")
    header()
    local res = runSet("A", lineup(sweepList(round.base)))
    local order, _, refs = report(res, "Sweep ranking")
    robustness(res, refs, ", sweep")
end

modes.holdout = function()
    holdSet = holdSet or "B"
    print("## Held-out seeds (set " .. holdSet .. ")\n")
    header()
    local res = runSet(holdSet, lineup(extras()))
    local order, _, refs = report(res, "Ranking on set " .. holdSet)
    detail(res, order)
    robustness(res, refs, ", set " .. holdSet)
end

-- Run 2: candidate fixes for rate changes, scored on the run 1 classes and the run 2 classes (S.RUN2).
local function p1(change, hints)
    return est(with(PREV, change or {}), hints)
end
-- Tuning grids (`tune --list grid1|grid2|grid3|learn`; results/run2-grid*.md): detector, half-life, learning.
local GRIDS = { grid1 = {}, grid2 = {} }
do
    local g = GRIDS.grid1
    for _, h in ipairs({ 2, 3, 4, 5 }) do
        for _, k in ipairs({ 0.25, 0.5, 0.75 }) do
            g[#g + 1] = { "Detector h=" .. h .. " k=" .. k, p1({ detect = h, detectK = k }) }
        end
    end
    for _, m in ipairs({ 2, 8 }) do
        g[#g + 1] = { "Detector h=3 k=0.5 min=" .. m, p1({ detect = 3, detectMin = m }) }
    end
    g[#g + 1] = { "Detector h=3 k=0.5 clip 2", p1({ detect = 3, detectClip = 2 }) }
    g[#g + 1] = { "Detector h=3 k=0.5 alpha 0.03", p1({ detect = 3, detectAlpha = 0.03 }) }
    g = GRIDS.grid2
    for _, d in ipairs({ { 4, 0.5 }, { 5, 0.25 } }) do
        local name = "Detector h=" .. d[1] .. " k=" .. d[2]
        local base = { detect = d[1], detectK = d[2] }
        g[#g + 1] = { name, p1(base) }
        for _, hl in ipairs({ 10, 15 }) do
            g[#g + 1] = { name .. " H=" .. hl, p1(with(base, { halfLife = hl })) }
        end
    end
    g[#g + 1] = { "No detector, H=10", p1({ halfLife = 10 }) }
    GRIDS.grid3 = {} -- full scale: the detector lets the fit forget more slowly
    g = GRIDS.grid3
    for _, d in ipairs({ { 5, 0.25 }, { 6, 0.25 }, { 4, 0.5 } }) do
        for _, hl in ipairs({ 6, 8, 10, 15 }) do
            local name = "Detector h=" .. d[1] .. " k=" .. d[2] .. " H=" .. hl
            g[#g + 1] = { name, p1({ detect = d[1], detectK = d[2], halfLife = hl }) }
        end
    end
    g[#g + 1] = { "No detector, H=15", p1({ halfLife = 15 }) }
    GRIDS.learn = {}
    g = GRIDS.learn
    for _, w in ipairs({ 0.3, 0.5, 0.8 }) do
        for _, s in ipairs({ 3, 5, 8 }) do
            local change = { detect = 5, detectK = 0.25, execAhead = true, execLearn = w, learnSpan = s }
            g[#g + 1] = { "Det + ahead, learned w=" .. w .. " span=" .. s, p1(change, { exec = "learn" }) }
            g[#g + 1] = { "Det + ahead, learned 20% always w=" .. w .. " span=" .. s, p1(change, { exec = "learn20" }) }
        end
    end
end
-- The run 2 lineup: the default (the detector, h=6 k=0.25), each hint on top of it ("Det +": the defaults; a fixed
-- declaration has learning off, "from the crossing" has execAhead off), then hints without the detector (no hint is
-- ever dropped there) for the risk.
local NOLEARN = { execLearn = 0 }
local RUN2 = {
    { "Run 2 default (estimator defaults)", est() },
    { "Run 2 default, H=15 (quieter option)", est({ halfLife = 15 }) },
    { "Det + rate hint, perfect", est({}, { rate = "perfect" }) },
    { "Det + rate hint, late 0.5-1 s", est({}, { rate = "late" }) },
    { "Det + rate hint, wrong (phantom)", est({}, { rate = "wrong" }) },
    { "Det + execute from the crossing, perfect", est({ execAhead = false, execLearn = 0 }, { exec = "perfect" }) },
    { "Det + execute from the crossing, x1.6", est({ execAhead = false, execLearn = 0 }, { exec = "fixed" }) },
    { "Det + execute ahead, perfect", est(NOLEARN, { exec = "perfect" }) },
    { "Det + execute ahead, x1.6", est(NOLEARN, { exec = "fixed" }) },
    { "Det + execute ahead, 20% x2 always", est(NOLEARN, { exec = "always" }) },
    { "Det + execute learned (true threshold, class session)", est({}, { exec = "learn" }) },
    { "Det + execute learned, 20% always (class session)", est({}, { exec = "learn20" }) },
    { "Det + execute learned, 20% always (one session)", est({}, { exec = "learnAll" }) },
    { "Det + execute from the crossing, learned", est({ execAhead = false }, { exec = "learn" }) },
    { "Det + rate hint + execute learned 20% (one session)", est({}, { rate = "perfect", exec = "learnAll" }) },
    { "Det + all hints perfect (ceiling)", est(NOLEARN, { rate = "perfect", exec = "perfect" }) },
    { "Rate hint, perfect (no detector)", p1({}, { rate = "perfect" }) },
    { "Rate hint, wrong (no detector)", p1({}, { rate = "wrong" }) },
    { "Execute ahead, perfect (no detector)", p1({ execAhead = true }, { exec = "perfect" }) },
    { "Execute ahead, 20% x2 always (no detector)", p1({ execAhead = true }, { exec = "always" }) },
}

local function run2Tables(res, order)
    local list = {
        { "unknown", "Unknown share", pct },
        { "relMed", "Relative error median", f },
        { "relP90", "Relative error p90", f },
        { "relXMed", "Relative error median, 10 s after a rate change", f },
        { "relXP90", "Relative error p90, 10 s after a rate change", f },
        { "wrongX", "Wrong side, 10 s after a rate change (mean of 4)", pct },
        { "relEMed", "Relative error median, early (first 25%)", f },
        { "relLMed", "Relative error median, late (last 25%)", f },
        { "relLP90", "Relative error p90, late (last 25%)", f },
        { "absMed", "Absolute error median s", f },
        { "wrongMean", "Wrong side (mean of 4 decisions)", pct },
        { "flipSum", "Excess flips per minute (sum of 4 decisions)", f },
        { "delayMed", "First answer median s", f },
    }
    for _, x in ipairs(list) do
        perClass(res, order, x[1], x[2], x[3])
    end
end

-- Both class sets, one compact row per algorithm: the old (run 1) score and the new (run 2) score, each against its
-- own main-lineup medians.
local function both(set, extra, title)
    local old = runSet(set, lineup(extra))
    local new = runSet(set, lineup(extra), S.RUN2)
    local so = scoreAll(old, mainSummaries(old))
    local sn = scoreAll(new, mainSummaries(new))
    local order = {}
    for a = 1, #old.algos do
        order[a] = a
    end
    table.sort(order, function(x, y)
        return so[x] + sn[x] < so[y] + sn[y]
    end)
    print("\n### " .. title .. "\n")
    print(
        "| algorithm | old score | old rel med/p90 | old wrong | old flips | new score | new unknown | new rel med/p90 | new post-change rel med/p90 | new post-change wrong | new wrong | new flips |"
    )
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for _, a in ipairs(order) do
        local o, n = old.overall[a], new.overall[a]
        print(
            string.format(
                "| %s | %s | %s / %s | %s | %s | %s | %s | %s / %s | %s / %s | %s | %s | %s |",
                old.algos[a][1],
                f(so[a], 3),
                f(o.relMed),
                f(o.relP90),
                pct(o.wrongMean),
                f(o.flipSum),
                f(sn[a], 3),
                pct(n.unknown),
                f(n.relMed),
                f(n.relP90),
                f(n.relXMed),
                f(n.relXP90),
                pct(n.wrongX),
                pct(n.wrongMean),
                f(n.flipSum)
            )
        )
    end
    return old, new, order
end

-- How often the detector drops a hint that was right: perfect rate hints and perfect execute declarations (the
-- default estimator), per class: fights with each, drops with both, with the rate hint only, with the execute only.
function modes.drops()
    holdSet = holdSet or "A"
    print("## Hints dropped under perfect hints (seed set " .. holdSet .. ")\n")
    print("| class | fights | with a lust | with an execute | drops, both hints | rate hint only | execute only |")
    print("|---|---|---|---|---|---|---|")
    local makes = {
        est({}, { rate = "perfect", exec = "perfect" }),
        est({}, { rate = "perfect" }),
        est({}, { exec = "perfect" }),
    }
    for _, list in ipairs({ S.CLASSES, S.RUN2 }) do
        for _, c in ipairs(list) do
            if c ~= "real" then
                local n = math.max(1, math.floor(COUNTS[c] * scale + 0.5))
                local rates, execs, drops = 0, 0, { 0, 0, 0 }
                for i = 1, n do
                    local seed = SEED_BASE[holdSet] + i * 7919 + (SEED_OFF[c] or #c) * 104729
                    local fight = S.build(c, seed)
                    local obs = O.build(fight, seed + 1)
                    obs.class, obs.session = c, {}
                    for m, make in ipairs(makes) do
                        local algo = make(obs)
                        O.run(obs, algo, {})
                        drops[m] = drops[m] + algo.e.drops
                    end
                    rates, execs = rates + (fight.lust and 1 or 0), execs + (fight.execute and 1 or 0)
                end
                print(
                    string.format(
                        "| %s | %d | %d | %d | %d | %d | %d |",
                        c,
                        n,
                        rates,
                        execs,
                        drops[1],
                        drops[2],
                        drops[3]
                    )
                )
            end
        end
    end
end

function modes.tune()
    holdSet = holdSet or "A"
    print("## Run 2 candidates on both class sets (seed set " .. holdSet .. ")\n")
    header()
    both(holdSet, GRIDS[tuneList] or RUN2, "Old and new classes")
end

-- Classes as rows, a few algorithms as columns: rel median / post-change rel median / wrong side.
local HEADLINE = {
    "Midpoints (TimeToDie default)",
    "Run 1 winner (pinned)",
    "Run 2 default (estimator defaults)",
    "Det + rate hint + execute learned 20% (one session)",
    "Det + all hints perfect (ceiling)",
}
local function headline(res)
    local idx = {}
    for i, name in ipairs(HEADLINE) do
        for a, spec in ipairs(res.algos) do
            if spec[1] == name then
                idx[i] = a
            end
        end
    end
    print("\n### Per class: rel median / rel median 10 s after a change / wrong side\n")
    print("| class | " .. table.concat(HEADLINE, " | ") .. " |")
    print("|---" .. string.rep("|---", #HEADLINE) .. "|")
    local function row(label, r)
        local cells = { label }
        for i = 1, #HEADLINE do
            local x = r(idx[i])
            cells[#cells + 1] = f(x.relMed) .. " / " .. f(x.relXMed) .. " / " .. pct(x.wrongMean)
        end
        print("| " .. table.concat(cells, " | ") .. " |")
    end
    for _, c in ipairs(res.classes) do
        row(c, function(a)
            return res.class[c][a]
        end)
    end
    row("**mean**", function(a)
        return res.overall[a]
    end)
end

function modes.run2()
    holdSet = holdSet or "A"
    print("## Run 2: execute and lust classes (seed set " .. holdSet .. ")\n")
    header()
    local res = runSet(holdSet, lineup(RUN2), S.RUN2)
    headline(res)
    local order = report(res, "Ranking on the run 2 classes (class means)")
    detail(res, order)
    run2Tables(res, order)
end

-- Run 3: partial-group execute (scenarios.lua S.RUN3). What the caller knows of the group: a run 3 fight carries its
-- session's group (classes known, the tank excluded); elsewhere the player is a 20% executor among members + 1 DPS
-- whose classes are unknown (no other execute assumed).
local function belief(obs)
    return obs.group or { own = 20, lines = { 20 }, nDPS = (obs.members or 0) + 1, nExec = 1 }
end

-- `hints.mode`: "none"; "own" (the player's own line, only when the player executes); "all" (the highest line in the
-- group: the estimator keeps one execute slot); "true" (the top line with the true group factor below it).
-- `hints.prior` { m, share }: the starting factor is 1 + executors counted x (m - 1) x share (share nil: 1 / the DPS
-- count; "own" counts the player, "all" every executing DPS); `hints.fixed`: start at this factor whatever the group.
-- The factor then learns (execLearn; 0 keeps it) and carries pull to pull inside a run 3 session (one group);
-- elsewhere each fight starts over (a new group). `hints.across`: one factor for the whole run (it does not reset
-- when the group changes). For the runner: algo.line (declared or false), algo.sess and algo.key (where the factor
-- is kept), algo.measured (streams that measured a speed-up).
local function est3(params, hints)
    local p = { spread = false }
    for k, v in pairs(params or {}) do
        p[k] = v
    end
    local key = {}
    return function(obs)
        local e = E.New(p)
        local g = belief(obs)
        local line, count = false, 0
        if hints.mode == "own" then
            line, count = g.own, 1
        elseif hints.mode == "all" or hints.mode == "true" then
            line, count = g.lines[1] or false, g.nExec
        end
        local start = 1
        if hints.prior then
            start = 1 + count * (hints.prior.m - 1) * (hints.prior.share or 1 / g.nDPS)
        elseif hints.fixed then
            start = hints.fixed
        elseif hints.mode == "true" and line and g.F then
            start = g.F[line]
        end
        local sess = obs.group and (hints.across and obs.across or obs.session)
        if line then
            e:Hint("execute", sess and sess[key] or start, line)
        end
        local algo = { e = e, line = line, sess = sess, key = key, measured = 0 }
        local cur = false
        function algo.restart()
            cur = false
            e:Restart()
        end
        function algo.band(_, t, lo, hi)
            e:Band(t, lo, hi)
        end
        function algo.get(_, now)
            if e.xCand and not cur then
                cur, algo.measured = true, algo.measured + 1
            end
            if line and sess then
                sess[key] = e:ExecuteFactor()
            end
            return (e:Get(now))
        end
        return algo
    end
end

local W25, FIX = { execLearn = 0.25 }, { execLearn = 0 }
local RUN3 = {
    { "a. no execute hint (default)", est3({}, { mode = "none" }), short = "a" },
    { "b. own line, learned", est3({}, { mode = "own" }), short = "b own" },
    { "b. all group lines (top line), learned", est3({}, { mode = "all" }), short = "b all" },
    { "b. own line, learned w=0.25", est3(W25, { mode = "own" }), short = "b own .25" },
    { "b. all lines, learned w=0.25", est3(W25, { mode = "all" }), short = "b all .25" },
    { "c. all lines, prior x2 equal share, learned", est3({}, { mode = "all", prior = { m = 2 } }), short = "c all" },
    { "c. own line, prior x2 equal share, learned", est3({}, { mode = "own", prior = { m = 2 } }), short = "c own" },
    {
        "c. all lines, prior x2 equal share, learned w=0.25",
        est3(W25, { mode = "all", prior = { m = 2 } }),
        short = "c all .25",
    },
    {
        "c. all lines, prior wrong share (1/8 each: too low), learned",
        est3({}, { mode = "all", prior = { m = 2, share = 0.125 } }),
        short = "c bad share",
    },
    {
        "c. all lines, prior wrong mult (x3: too high), learned",
        est3({}, { mode = "all", prior = { m = 3 } }),
        short = "c bad mult",
    },
    { "d. all lines, prior x2 equal share, fixed", est3(FIX, { mode = "all", prior = { m = 2 } }), short = "d" },
    {
        "d. all lines, prior wrong share (1/8 each: too low), fixed",
        est3(FIX, { mode = "all", prior = { m = 2, share = 0.125 } }),
        short = "d bad share",
    },
    {
        "d. all lines, prior wrong mult (x3: too high), fixed",
        est3(FIX, { mode = "all", prior = { m = 3 } }),
        short = "d bad mult",
    },
    { "d. all lines, x2 whatever the group, fixed", est3(FIX, { mode = "all", fixed = 2 }), short = "d x2" },
    {
        "b. all lines, learned, one factor across groups",
        est3({}, { mode = "all", across = true }),
        short = "b all across",
    },
    { "ceiling: true group factor at the top line, fixed", est3(FIX, { mode = "true" }), short = "ceiling" },
}

-- `run3 --list learn`: the learning weight for threshold-only and prior starts.
local RUN3_LEARN = { RUN3[1] }
for _, w in ipairs({ 0.1, 0.15, 0.25, 0.35, 0.5, 0.7 }) do
    local p = { execLearn = w }
    RUN3_LEARN[#RUN3_LEARN + 1] = { "b. all lines, learned w=" .. w, est3(p, { mode = "all" }), short = "b " .. w }
    RUN3_LEARN[#RUN3_LEARN + 1] =
        { "c. all lines, prior x2, learned w=" .. w, est3(p, { mode = "all", prior = { m = 2 } }), short = "c " .. w }
end

local LENGTHS = { "trash", "elite", "boss" }
local SESSIONS = 16 -- per composition and seed set (x 10 pulls)
-- First against later pulls of a session: the first and last trash and elite pulls.
local PULL_BUCKET = { [1] = "trash, pull 1", [10] = "trash, pull 10", [2] = "elite, pull 2", [9] = "elite, pull 9" }
local PULL_ORDER = { "trash, pull 1", "trash, pull 10", "elite, pull 2", "elite, pull 9" }

local function runSet3(set, algos)
    local main = {}
    for a, spec in ipairs(algos) do
        if spec.main then
            main[#main + 1] = a
        end
    end
    local stats, classes = {}, {}
    local function bucket(name)
        if not stats[name] then
            stats[name] = {}
            for a = 1, #algos do
                stats[name][a] = M.newStats()
            end
        end
        return stats[name]
    end
    for _, comp in ipairs(S.RUN3) do
        for _, len in ipairs(LENGTHS) do
            classes[#classes + 1] = comp.name .. " " .. len
            bucket(classes[#classes])
        end
    end
    local conv, factors, across = {}, {}, {} -- conv[a][pull] = { r = learned / true factors, m = streams measured }
    for a = 1, #algos do
        conv[a] = {}
    end
    local nSess = math.max(1, math.floor(SESSIONS * scale + 0.5))
    for _, comp in ipairs(S.RUN3) do
        factors[comp.name] = {}
    end
    for s = 1, nSess do -- sessions round robin over the compositions: the `across` factor meets a new group each time
        for ci, comp in ipairs(S.RUN3) do
            local sseed = SEED_BASE[set] + 3000000 + s * 7919 + ci * 104729
            local group = S.group(comp, sseed)
            factors[comp.name][s] = group
            local session = {}
            -- pull seeds from their own generator: nearby seeds share a first draw (pack size, elite length) with
            -- each other and with the group's first rate; the first draw here tracks it too, so it is burnt
            local srng = require("rng").new(sseed + 17)
            srng:next()
            for pi, len in ipairs(S.PULLS) do
                local seed = srng:int(1, 2147483000)
                local obs = O.build(S.build(len, seed, group), seed + 1)
                obs.class, obs.session, obs.across = comp.name, session, across
                local answers, made = {}, {}
                for a, spec in ipairs(algos) do
                    made[a] = spec[2](obs)
                    answers[a] = O.run(obs, made[a], {})
                end
                M.add(obs, answers, stats[comp.name .. " " .. len], main)
                if PULL_BUCKET[pi] and group.nExec > 0 then
                    M.add(obs, answers, bucket((comp.solo and "solo " or "group ") .. PULL_BUCKET[pi]), main)
                end
                for a = 1, #algos do
                    local algo = made[a]
                    if #group.lines == 1 and algo.line and algo.sess then
                        local c = conv[a][pi] or { r = {}, m = 0 }
                        conv[a][pi] = c
                        c.r[#c.r + 1] = (algo.sess[algo.key] or 1) / group.F[algo.line]
                        c.m = c.m + algo.measured
                    end
                end
            end
        end
    end
    local res = { algos = algos, class = {}, overall = {}, classes = classes, pull = {}, conv = conv }
    res.factors, res.nSess = factors, nSess
    for name, per in pairs(stats) do
        res.class[name] = {}
        for a = 1, #algos do
            res.class[name][a] = M.summary(per[a])
        end
    end
    for a = 1, #algos do
        local per = {}
        for _, c in ipairs(classes) do
            per[#per + 1] = res.class[c][a]
        end
        res.overall[a] = M.mean(per)
    end
    return res
end

-- A table with one row per name and one column per run 3 strategy (short labels): cell(summary) of row(name)[a].
local function grid3(res, title, names, row, cell)
    local cols = {}
    for a, spec in ipairs(res.algos) do
        if spec.short then
            cols[#cols + 1] = a
        end
    end
    print("\n### " .. title .. "\n")
    local head = { "| scenario" }
    for _, a in ipairs(cols) do
        head[#head + 1] = res.algos[a].short
    end
    print(table.concat(head, " | ") .. " |")
    print("|---" .. string.rep("|---", #cols) .. "|")
    for _, name in ipairs(names) do
        local r = row(name)
        local cells = { "| " .. name }
        for _, a in ipairs(cols) do
            cells[#cells + 1] = cell(r[a], a)
        end
        print(table.concat(cells, " | ") .. " |")
    end
end

local function run3Tables(res, refs)
    print("\n### Groups (per session: the player's line, the lines present, true group factor below each line)\n")
    print("| composition | executing DPS | own line | group factor below the top line, mean (min-max) | below 20% |")
    print("|---|---|---|---|---|")
    for _, comp in ipairs(S.RUN3) do
        local top, low, lo, hi = 0, 0, 9, 0
        local list = res.factors[comp.name]
        for _, g in ipairs(list) do
            local ft = g.lines[1] and g.F[g.lines[1]] or 1
            top, low = top + ft, low + (g.lines[1] and g.F[g.lines[#g.lines]] or 1)
            lo, hi = math.min(lo, ft), math.max(hi, ft)
        end
        local g = list[1]
        print(
            string.format(
                "| %s | %d of %d | %s | %.2f (%.2f-%.2f) | %.2f |",
                comp.name,
                g.nExec,
                g.nDPS,
                g.own and (g.own .. "%") or "none",
                top / #list,
                lo,
                hi,
                low / #list
            )
        )
    end
    local comps = {}
    for _, comp in ipairs(S.RUN3) do
        comps[#comps + 1] = comp.name
    end
    local mean = {}
    local function byComp(name)
        if not mean[name] then
            local out = {}
            for a = 1, #res.algos do
                local per = {}
                for _, len in ipairs(LENGTHS) do
                    per[#per + 1] = res.class[name .. " " .. len][a]
                end
                out[a] = M.mean(per)
            end
            mean[name] = out
        end
        return mean[name]
    end
    local function byClass(name)
        return res.class[name]
    end
    comps[#comps + 1] = "**mean**"
    mean["**mean**"] = res.overall
    grid3(
        res,
        "Score per composition (lengths averaged; refs: the main lineup on all run 3 buckets)",
        comps,
        byComp,
        function(r)
            return f(M.score(r, refs), 3)
        end
    )
    grid3(res, "Relative error median per composition", comps, byComp, function(r)
        return f(r.relMed)
    end)
    grid3(res, "Relative error median, 10 s after a line crossing, per composition", comps, byComp, function(r)
        return f(r.relXMed)
    end)
    grid3(res, "Relative error p90 per composition", comps, byComp, function(r)
        return f(r.relP90)
    end)
    for d, label in ipairs({ "ttd<4", "ttd<8", "ttd<15", "fight_remains<20" }) do
        grid3(res, "Wrong side " .. label .. " per composition", comps, byComp, function(r)
            return pct(r.wrong[d])
        end)
    end
    grid3(res, "Excess flips per minute (sum of 4) per composition", comps, byComp, function(r)
        return f(r.flipSum)
    end)
    grid3(res, "Unknown share per composition", comps, byComp, function(r)
        return pct(r.unknown)
    end)
    grid3(
        res,
        "Relative error median / 10 s after a crossing, per composition and length",
        res.classes,
        byClass,
        function(r)
            return f(r.relMed) .. " / " .. f(r.relXMed)
        end
    )
    local pulls = {}
    for _, who in ipairs({ "group ", "solo " }) do
        for _, b in ipairs(PULL_ORDER) do
            pulls[#pulls + 1] = who .. b
        end
    end
    grid3(res, "First against later pulls (groups with an executor; rel med / wrong ttd<8)", pulls, byClass, function(r)
        return f(r.relMed) .. " / " .. pct(r.wrong[2])
    end)
    print("\n### Learning: learned / true group factor after each pull (single-line groups, declared line)\n")
    print(
        "Cells: median |ratio - 1| / median ratio / share within 10%; streams measured per session up to that pull.\n"
    )
    local cols = {}
    for a, spec in ipairs(res.algos) do
        if spec.short and res.conv[a][1] then
            cols[#cols + 1] = a
        end
    end
    local head = { "| pull" }
    for _, a in ipairs(cols) do
        head[#head + 1] = res.algos[a].short
    end
    print(table.concat(head, " | ") .. " | streams measured (b all) |")
    print("|---" .. string.rep("|---", #cols + 1) .. "|")
    local acc = {}
    for pi = 1, #S.PULLS do
        local cells = { "| " .. pi .. " " .. S.PULLS[pi] }
        local measured
        for _, a in ipairs(cols) do
            local c = res.conv[a][pi]
            local dev, within = {}, 0
            for i, r in ipairs(c.r) do
                dev[i] = math.abs(r - 1)
                within = within + (dev[i] <= 0.1 and 1 or 0)
            end
            table.sort(dev)
            local rs = {}
            for i, r in ipairs(c.r) do
                rs[i] = r
            end
            table.sort(rs)
            local mid = math.ceil(#rs / 2)
            cells[#cells + 1] = f(dev[mid]) .. " / " .. f(rs[mid]) .. " / " .. pct(within / #c.r)
            if res.algos[a].short == "b all" then
                acc[a] = (acc[a] or 0) + c.m
                measured = acc[a] / #c.r
            end
        end
        cells[#cells + 1] = f(measured, 1)
        print(table.concat(cells, " | ") .. " |")
    end
end

function modes.run3()
    holdSet = holdSet or "A"
    print("## Run 3: partial-group execute (seed set " .. holdSet .. ")\n")
    header()
    local res = runSet3(holdSet, lineup(tuneList == "learn" and RUN3_LEARN or RUN3))
    local order, _, refs = report(res, "Ranking on the run 3 buckets (composition x length, class means)")
    detail(res, order)
    run3Tables(res, refs)
end

-- Run 3 strategies on the run 1 and run 2 classes (no regression): the player declares 20%, the members' classes
-- are unknown, every fight is a new group (learning only inside a fight).
local RUN3_OLD = {
    RUN3[1],
    RUN3[2],
    RUN3[4],
    RUN3[7],
    RUN3[9],
    RUN3[11],
    RUN3[13],
    RUN3[14],
    { "Run 2 recommendation: 20% learned, one session", est({}, { exec = "learnAll" }) },
    { "Run 2 recommendation, learned w=0.25", est(W25, { exec = "learnAll" }) },
}

function modes.run3old()
    holdSet = holdSet or "A"
    print("## Run 3 strategies on the run 1 and run 2 classes (seed set " .. holdSet .. ")\n")
    header()
    both(holdSet, RUN3_OLD, "Old and new classes")
end

function modes.all()
    modes.test()
    modes.main()
    for r = 1, #ROUNDS do
        sweepRound = r
        modes.sweep()
    end
    modes.holdout()
end

local t0 = os.clock()
assert(modes[mode], "mode: main|sweep|holdout|run2|tune|drops|run3|run3old|test|all")()
io.stderr:write(string.format("ttd lab %s done in %.1f s\n", mode, os.clock() - t0))
