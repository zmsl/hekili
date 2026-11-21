-- tools/ttd_lab/run.lua: the TTD lab. From the repo root: lua5.1 tools/ttd_lab/run.lua
-- [main|sweep|holdout|run2|tune|test|all] [--scale x] [--round n] (sweep round, default the last) [--set A|B|C] (seed
-- set: holdout defaults to B, run2 and tune to A). Prints markdown tables (tools/ttd_lab/README.md explains them).
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
    holdSet = holdSet or (mode == "holdout" and "B" or "A")
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
local PREV = { detect = 0, execAhead = false }

-- `hints` (run 2): rate = "perfect" (the lust as it starts, its true end), "late" (the caller sees it 0.5-1 s late:
-- startT and endT are the call time and call time + 40 s), "wrong" (no real lust is passed; a phantom x1.3 for 40 s
-- 5 s after the fight's first unit); exec = "perfect" (the fight's true threshold and multiplier), "fixed" (the
-- true threshold, x1.6 whatever the group does), "always" (20% x2 declared on every fight, execute or not), "learn"
-- (the true threshold, the factor learned: it starts at 1 and each fight starts from the factor the previous fight
-- of its class ended with, as a session would; needs `execLearn`), "learn20" (the same with 20% on every fight).
local function est(params, hints)
    local p = { spread = false }
    for k, v in pairs(params or {}) do
        p[k] = v
    end
    hints = hints or {}
    local session = {} -- class -> the learned execute factor
    return function(obs)
        local e = E.New(p)
        local x = obs and obs.execute
        local learnPct = hints.exec == "learn" and x and x.pct or hints.exec == "learn20" and 20
        if hints.exec == "perfect" and x then
            e:Hint("execute", x.mult, x.pct)
        elseif hints.exec == "fixed" and x then
            e:Hint("execute", 1.6, x.pct)
        elseif hints.exec == "always" then
            e:Hint("execute", 2, 20)
        elseif learnPct then
            e:Hint("execute", session[obs.class] or 1, learnPct)
        end
        local pendAt, pendMult, firstT, phantom = nil, nil, nil, false
        local function due(now)
            if pendAt and now >= pendAt then
                e:Hint("rate", pendMult, pendAt, pendAt + 40)
                pendAt = nil
            end
        end
        return {
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
                    session[obs.class] = e:ExecuteFactor()
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
local RESEARCH = with(PREV, { censor = 1, anchorBelow = false, priorEmpty = false, holdStall = false, shrink = 2, window = 18 })

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
    local stats = {}
    for _, c in ipairs(classes) do
        stats[c] = {}
        for a = 1, #algos do
            stats[c][a] = M.newStats()
        end
    end
    local function one(class, fight, oseed)
        local obs = O.build(fight, oseed)
        obs.class = class
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
        algos[#algos + 1] = { spec[1], spec[2], params = spec.params }
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

local function extras()
    local extra = {}
    for _, list in ipairs({ ABLATION, CANDIDATES }) do
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
-- Detector tuning grids (`tune --list grid1|grid2`; results/run2-grid*.md).
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
-- The run 2 lineup: the detector alone (the new default candidate), then each hint on top of it, then hints without
-- the detector (no hint is ever dropped there) for the risk.
local DET = { detect = 5, detectK = 0.25 }
local function d1(change, hints)
    return p1(with(DET, change or {}), hints)
end
local RUN2 = {
    { "Detector h=5 k=0.25", d1() },
    { "Detector h=5 k=0.25, H=10", d1({ halfLife = 10 }) },
    { "Detector h=4 k=0.5", p1({ detect = 4 }) },
    { "Det + rate hint, perfect", d1({}, { rate = "perfect" }) },
    { "Det + rate hint, late 0.5-1 s", d1({}, { rate = "late" }) },
    { "Det + rate hint, wrong (phantom)", d1({}, { rate = "wrong" }) },
    { "Det + execute from the crossing, perfect", d1({}, { exec = "perfect" }) },
    { "Det + execute from the crossing, x1.6", d1({}, { exec = "fixed" }) },
    { "Det + execute from the crossing, 20% x2 always", d1({}, { exec = "always" }) },
    { "Det + execute ahead, perfect", d1({ execAhead = true }, { exec = "perfect" }) },
    { "Det + execute ahead, x1.6", d1({ execAhead = true }, { exec = "fixed" }) },
    { "Det + execute ahead, 20% x2 always", d1({ execAhead = true }, { exec = "always" }) },
    { "Det + execute ahead, learned", d1({ execAhead = true, execLearn = 0.5 }, { exec = "learn" }) },
    { "Det + execute ahead, learned, 20% always", d1({ execAhead = true, execLearn = 0.5 }, { exec = "learn20" }) },
    { "Det + execute from the crossing, learned", d1({ execLearn = 0.5 }, { exec = "learn" }) },
    { "Det + all hints perfect (ceiling)", d1({ execAhead = true }, { rate = "perfect", exec = "perfect" }) },
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

function modes.tune()
    print("## Run 2 candidates on both class sets (seed set " .. holdSet .. ")\n")
    header()
    both(holdSet, GRIDS[tuneList] or RUN2, "Old and new classes")
end

function modes.run2()
    print("## Run 2: execute and lust classes (seed set " .. holdSet .. ")\n")
    header()
    local res = runSet(holdSet, lineup(RUN2), S.RUN2)
    local order = report(res, "Ranking on the run 2 classes (class means)")
    detail(res, order)
    run2Tables(res, order)
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
assert(modes[mode], "mode: main|sweep|holdout|test|all")()
io.stderr:write(string.format("ttd lab %s done in %.1f s\n", mode, os.clock() - t0))
