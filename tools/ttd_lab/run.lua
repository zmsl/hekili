-- tools/ttd_lab/run.lua: the TTD lab. From the repo root: lua5.1 tools/ttd_lab/run.lua [main|sweep|holdout|test|all]
-- [--scale x] [--round n] (sweep round, default the last). Prints markdown tables (tools/ttd_lab/README.md explains them).
package.path = "tools/ttd_lab/?.lua;" .. package.path

local S, O, Real = require("scenarios"), require("observe"), require("real")
local B, E, M = require("baselines"), require("estimator"), require("metrics")

local mode, scale, sweepRound = "main", 1, nil
do
    local i = 1
    while arg[i] do
        if arg[i] == "--scale" then
            scale, i = tonumber(arg[i + 1]), i + 1
        elseif arg[i] == "--round" then
            sweepRound, i = tonumber(arg[i + 1]), i + 1
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
local SEED_BASE = { A = 1000, B = 900000 }

local function est(params)
    local p = { spread = false }
    for k, v in pairs(params or {}) do
        p[k] = v
    end
    return function()
        local e = E.New(p)
        return {
            restart = function()
                e:Restart()
            end,
            band = function(_, t, lo, hi)
                e:Band(t, lo, hi)
            end,
            get = function(_, now)
                return (e:Get(now))
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
local RESEARCH = { censor = 1, anchorBelow = false, priorEmpty = false, holdStall = false, shrink = 2, window = 18 }

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
    { "Winner (estimator defaults)", est() },
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
    { "Winner, no deadband", est({ hystAbs = 0 }) },
    { "Winner + censoring (research rule)", est({ censor = 1 }) },
    { "Winner, no full anchor", est({ anchorFull = false }) },
    { "Winner, no below-full anchor", est({ anchorBelow = false }) },
    { "Winner, no carried prior", est({ prior = false }) },
    { "Winner, carried prior only after a crossing", est({ priorEmpty = false }) },
    { "Winner, no stall hold", est({ holdStall = false }) },
    { "Winner, K=2 (research shrink)", est({ shrink = 2 }) },
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
    { name = "round 5, base = the winner (estimator defaults)", base = {} },
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

local function runSet(set, algos)
    local main = {}
    for a, spec in ipairs(algos) do
        if spec.main then
            main[#main + 1] = a
        end
    end
    local stats = {}
    for _, c in ipairs(S.CLASSES) do
        stats[c] = {}
        for a = 1, #algos do
            stats[c][a] = M.newStats()
        end
    end
    local function one(class, fight, oseed)
        local obs = O.build(fight, oseed)
        local answers = {}
        for a, spec in ipairs(algos) do
            answers[a] = O.run(obs, spec[2](), {})
        end
        M.add(obs, answers, stats[class], main)
    end
    local base = SEED_BASE[set]
    for _, c in ipairs(S.CLASSES) do
        if c ~= "real" then
            for i = 1, math.max(1, math.floor(COUNTS[c] * scale + 0.5)) do
                local seed = base + i * 7919 + #c * 104729
                one(c, S.build(c, seed), seed + 1)
            end
        end
    end
    local logs = Real.logs()
    for li, name in ipairs(logs) do
        if (li - 1) % math.max(1, math.floor(1 / scale + 0.5)) == 0 then
            local ts, as = Real.hits(name)
            for di, d in ipairs(Real.DEATHS) do
                one("real", Real.fight(ts, as, d), base + li * 31 + di)
            end
        end
    end
    local result = { algos = algos, class = {}, overall = {} }
    for a = 1, #algos do
        local per = {}
        for _, c in ipairs(S.CLASSES) do
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
    for _, c in ipairs(S.CLASSES) do
        head[#head + 1] = c
        sep[#sep + 1] = "---"
    end
    print(table.concat(head, " | ") .. " |")
    print(table.concat(sep, "|") .. "|")
    for _, a in ipairs(order) do
        local cells = { "| " .. res.algos[a][1] }
        for _, c in ipairs(S.CLASSES) do
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
    perClass(res, order, "wrongMean", "Wrong side (mean of 4 decisions)", pct)
    perClass(res, order, "flipSum", "Excess flips per minute (sum of 4 decisions)", f)
    perClass(res, order, "delayMed", "First answer median s", f)
    robustness(res, refs)
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
    print("## Held-out seeds (set B)\n")
    header()
    local res = runSet("B", lineup(extras()))
    local order, _, refs = report(res, "Ranking on set B")
    detail(res, order)
    robustness(res, refs, ", set B")
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
