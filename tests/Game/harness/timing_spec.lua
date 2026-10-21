-- tests/Game/harness/timing_spec.lua: the ready-time module (docs/dev/ready-time-design.md) on synthetic logs and polls.
local timing = require("Game.harness.timing")

local POWER = { mana = 0, rage = 1 }

-- a log's events in line order, each at world time pull + t + its place within the timestamp (replay.lua's wt)
local function events(list, pull)
    local seq = {}
    for _, e in ipairs(list) do
        local n = (seq[e.t] or 0) + 1
        seq[e.t] = n
        e.wt = pull + e.t + n * 1e-6
    end
    return list
end

local function cast(t, id, o)
    o = o or {}
    return { kind = "casting", t = t, id = id, cost = o.cost or 0, cast = 0, gcd = o.gcd or 1.5, tag = o.tag }
end
local function power(t, name, from, to, o)
    o = o or {}
    return { kind = "power", t = t, name = name, from = from, to = to, id = o.id, other = o.other }
end

-- a replay's R for `ev`: every casting a decision (keyFor: the ID's key), sorted
local KEY = { [1] = "a", [2] = "b", [3] = "c", [4] = "d" }
local function bind(ev, cd, pull)
    local R = { pull = pull, decisions = {}, casts = {} }
    for _, e in ipairs(ev) do
        if e.kind == "casting" and KEY[e.id] then
            local d = { t = e.wt - 5e-7, key = KEY[e.id], gcd = e.cast > 0 or e.gcd > 0 }
            R.decisions[#R.decisions + 1], R.casts[#R.casts + 1] = d, d
        end
    end
    local T = timing.new(R, ev, function(e)
        return KEY[e.id]
    end, cd or {}, POWER)
    return R, T
end

describe("timing.new: each decision's ready class from the log", function()
    it("names prepull, the first GCD, GCD, cost (swing or tick), cooldown, aura and slack", function()
        local ev = events({
            cast(-1, 1), -- prepull
            cast(0.1, 2), -- the first on-GCD cast at or after 0
            cast(1.6, 2), -- at the previous GCD's end
            power(3.1, "rage", 5, 25, { other = 3 }), -- a swing crosses c's cost of 20 at the GCD's end
            cast(3.1, 3, { cost = 20 }),
            power(3.1, "rage", 25, 5, { id = 3 }), -- its spend: the pool
            cast(6.0, 2), -- b's cooldown (4.4) ends at 6.0; the GCD long over
            { kind = "aura", t = 9, unit = "player", verb = "gained", id = 900099 },
            cast(9.0, 4), -- an aura line in its timestamp
            cast(12.0, 4), -- nothing: wowsims waited
            power(13.9, "mana", 9, 10, { other = 2 }),
            power(14.0, "mana", 10, 11, { other = 2 }), -- a regen tick crosses d2's cost of 11
            cast(14.0, 1, { cost = 11 }),
            power(14.0, "mana", 11, 0, { id = 1 }),
        }, 5)
        local R, T = bind(ev, { a = 0, b = 4.4, c = 0, d = 0 }, 5)
        local got = {}
        for i, d in ipairs(R.decisions) do
            got[i] = d.cls
        end
        assert.are.same({ "prepull", "first", "gcd", "cost", "cooldown", "aura", "slack", "cost" }, got)
        assert.are.same({ 1, true, 20 }, { R.decisions[4].pt, R.decisions[4].swing, R.decisions[4].cost })
        assert.are.same({ 0, false }, { R.decisions[8].pt, R.decisions[8].swing })
        assert.are.same({ c = 1, a = 0 }, T.costed)
        assert.are.equal(9, R.decisions[6].lt)
    end)

    it("finds a hard cast's pool from its spend at the cast's end", function()
        local ev = events({
            cast(0.1, 2),
            power(1.6, "rage", 10, 20, { other = 3 }),
            { kind = "casting", t = 1.6, id = 3, cost = 15, cast = 1, gcd = 1.5 },
            power(2.6, "rage", 20, 5, { id = 3 }),
        }, 5)
        local R = bind(ev, { b = 0, c = 0 }, 5)
        assert.are.same({ "cost", 1 }, { R.decisions[2].cls, R.decisions[2].pt })
    end)

    it("names an off-GCD queue (tag 1, no cost) and the strike that lands from it", function()
        local ev = events({
            cast(0.1, 2),
            cast(0.5, 4, { tag = 1, gcd = 0 }),
            cast(2.2, 4, { cost = 12, gcd = 0 }),
            power(2.2, "rage", 30, 18, { id = 4 }),
        }, 5)
        local R = bind(ev, { b = 0, d = 0 }, 5)
        assert.are.same({ "first", "queue", "landing" }, { R.decisions[1].cls, R.decisions[2].cls, R.decisions[3].cls })
        assert.is_false(R.decisions[2].gcd)
    end)
end)

-- a poll: { t, { name, wait, off }... } as timing.poll records it
local function poll(T, t, list, band)
    local p = { t = t, name = {}, wait = {}, off = {}, n = #list }
    for i, r in ipairs(list) do
        p.name[i], p.wait[i], p.off[i] = r[1], r[2], r[3] or false
    end
    for pt, v in pairs(band or {}) do
        p[pt] = v
    end
    T.polls[#T.polls + 1] = p
end

describe("timing.rows: the shown and predicted offsets at each decision", function()
    local P = { REACT = 0.05, EDGE = 1e-3, G7 = 0.1, HOLD = 0.1, TICK = 0.1, reaction = 0.1, queue = 0.25 }
    it("walks back to the first ready poll, reads a late wait at the decision, and leaves a miss unshown", function()
        local ev = events({
            cast(0.1, 2),
            cast(1.6, 1),
            power(3.1, "rage", 10, 25, { other = 3 }),
            cast(3.1, 3, { cost = 20 }),
            power(3.1, "rage", 25, 5, { id = 3 }),
            cast(4.6, 2),
        }, 5)
        local R, T = bind(ev, { a = 0, b = 0, c = 0 }, 5)
        local d = R.decisions
        poll(T, d[1].t, { { "b", 0 } })
        poll(T, 6.2, { { "a", 0.4 } }) -- a predicted at 6.6 (cast at 6.6): a = 0
        poll(T, 6.4, { { "x", 0, true }, { "a", 0 } }) -- an off-GCD icon first: a shown first on-GCD, ready
        poll(T, d[2].t, { { "a", 0 } })
        poll(T, 7.8, { { "c", 0.3 } })
        poll(T, d[3].t, { { "c", 0.2 } }, { [1] = { -4, 1 } }) -- shown 0.2 s late; the floor 4 under the truth
        poll(T, 9.4, { { "c", 0 } })
        poll(T, d[4].t, { { "c", 0 } }) -- b never shown
        local rows = timing.rows(T, P)
        local function pick(r)
            return { r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] }
        end
        assert.are.same({ 0.1, "b", "first", "on", 0, nil, "scope", nil, nil }, pick(rows[1]))
        -- first shown ready at 6.4, 0.2 s before the GCD's end: early (beyond the grain); predicted from 6.4 too
        assert.are.same({ 1.6, "a", "gcd", "on", -0.2, -0.2, "early", nil, nil }, pick(rows[2]))
        assert.are.same({ 3.1, "c", "cost", "on", 0.2, 0, "in:cost", -4, 1 }, pick(rows[3]))
        assert.are.same({ 4.6, "b", "gcd", "on", nil, nil, "never", nil, nil }, pick(rows[4]))
    end)
end)

describe("timing.verdict: the tolerance windows (design §3)", function()
    local P = { REACT = 0.05, EDGE = 1e-3, G7 = 0.1, HOLD = 0.1, TICK = 0.1, reaction = 0.1, queue = 0.25 }
    it("absorbs grain, the cost lag, wowsims's reaction and the queue; the rest is real", function()
        local cases = {
            { "first", 3, false, false, "scope" },
            { "gcd", nil, false, true, "in:tie" },
            { "gcd", nil, false, false, "never" },
            { "gcd", -0.05, false, false, "in:grain" },
            { "gcd", 0.2, false, false, "late" },
            { "cost", 0.2, true, false, "in:cost" },
            { "cost", 0.25, false, false, "late" },
            { "cost", -0.2, false, false, "early" },
            { "cooldown", 0.5, false, false, "late" },
            { "slack", -0.15, false, false, "in:reaction" },
            { "aura", -0.2, false, false, "early" },
            { "queue", 0.25, false, false, "in:queue" },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[5], timing.verdict(c[1], c[2], c[3], c[4], P), c[1] .. " " .. tostring(c[2]))
        end
    end)
end)

describe("timing.summary and line", function()
    it("floors the real on-GCD rows, keeps scope and off-GCD apart, and bands the cost-gated rows", function()
        local rows = {
            { 0.1, "a", "first", "on", 0, nil, "scope" },
            { 1.6, "a", "gcd", "on", 0, 0, "in:grain" },
            { 3.1, "c", "cost", "on", 0.2, 0, "in:cost", -4, 1 },
            { 4.6, "b", "gcd", "on", 0.8, 0.8, "late" },
            { 6.1, "b", "slack", "on", -0.4, -0.4, "early" },
            { 7.6, "c", "cost", "on", nil, nil, "never", -2, 0 },
            { 8.0, "d", "cooldown", "off", 0.3, 0.3, "late" },
        }
        local s = timing.summary(rows, { { -1, 0 } }) -- medians are the lower one (loop.lua's quantile)
        assert.are.same(
            { 5, 4, 1, 1, 2, 0.4, 1, 1 },
            { s.n, s.timed, s.never, s.scope, s.real, s.realMedian, s.earlyReal, s.lateReal }
        )
        assert.are.same({ 1, 0.3 }, { s.offReal, s.offMedian })
        local line = timing.line(s)
        assert.is_truthy(line:find("real 2 (early 1 late 1) median 0.400; absorbed [cost 1, grain 1]", 1, true), line)
        assert.is_truthy(line:find("cost-gated lo-truth -4.0 p90 4.0 est-truth 0.0 p90 1.0 (2)", 1, true), line)
    end)
end)
