-- tests/Game/harness/flicker_spec.lua: the flicker ledger (kinds, cause classes, the summary line) and the display-side
-- hold switch, on synthetic per-tick frames (class-neutral: abilities a, b, c, x).
local flicker = require("Game.harness.flicker")

local TICK, REACT = 0.2, 0.05

-- rows: { s = { { name, wait, cost }, ... (slots 1-4) }, lo, est, hi, truth, pend, cd = { [name] = s }, ev = { cast = true } }
local function build(rows)
    local ev = flicker.events()
    local f = flicker.frame(ev)
    for n, r in ipairs(rows) do
        f.n = n
        for s = 1, flicker.SLOTS do
            local x = r.s[s] or {}
            f.name[s][n], f.wait[s][n], f.cost[s][n] = x[1] or false, x[2] or 0, x[3] or 0
        end
        f.lo[n], f.est[n], f.truth[n] = r.lo or 50, r.est or r.lo or 50, r.truth or r.est or r.lo or 50
        f.hi[n], f.pend[n], f.cd[n], f.gcd[n], f.t[n] =
            r.hi or f.est[n], r.pend or false, r.cd or {}, r.gcd or 0, n * TICK
        for _, k in ipairs(flicker.EVENTS) do
            ev[k][n] = (r.ev or {})[k] or false
        end
    end
    return f
end

local function kinds(led)
    local out = {}
    for _, e in ipairs(led.entries) do
        out[#out + 1] = e.kind .. " " .. tostring(e.from) .. ">" .. tostring(e.to) .. " " .. e.cause .. " " .. e.len
    end
    return out
end

local O = { tick = TICK, react = REACT }

describe("the flicker ledger", function()
    it("records a dip (the icon returns) with its cause: a near-tie when the two waits were within a poll", function()
        local f = build({
            { s = { { "a", 0.4 }, { "b", 0.5 } } },
            { s = { { "a", 0.2 }, { "b", 0.3 } } },
            { s = { { "b", 0.1 }, { "a", 0.15 } } },
            { s = { { "a", 0.2 }, { "b", 0.3 } } },
            { s = { { "a", 0.0 }, { "b", 0.1 } } },
        })
        local got = kinds(flicker.ledger(f, O))
        -- slot 1 dips a for one tick; slot 2 dips b the same tick (the two swap)
        assert.are.same({ "dip a>b near-tie 1", "dip b>a near-tie 1" }, got)
    end)

    it(
        "records a flash (an icon appears and vanishes, the slot moves on), its cause a provisional credit vetoed",
        function()
            local f = build({
                { s = { { "a", 0.5 } }, est = 30 },
                { s = { { "a", 0.3 } }, est = 30 },
                { s = { { "b", 0.0 } }, est = 30 },
                { s = { { "c", 0.4 } }, est = 26 }, -- est fell with no spend: the flash's end is a vetoed credit
                { s = { { "c", 0.2 } }, est = 26 },
                { s = { { "c", 0.0 } }, est = 26 },
                { s = { { "c", 0.0 } }, est = 26 },
                { s = { { "c", 0.0 } }, est = 26 },
                { s = { { "c", 0.0 } }, est = 26 },
            })
            assert.are.same({ "flash a>b unknown 1" }, kinds(flicker.ledger(f, O)))
            -- the cause is the belief's change at the flash's start: a credit taken back at its end shows on the dip
            f = build({
                { s = { { "a", 0.5 } }, est = 30 },
                { s = { { "a", 0.3 } }, est = 30 },
                { s = { { "b", 0.0 } }, est = 27 },
                { s = { { "c", 0.4 } }, est = 27 },
                { s = { { "c", 0.2 } }, est = 27 },
                { s = { { "c", 0.2 } }, est = 27 },
                { s = { { "c", 0.2 } }, est = 27 },
                { s = { { "c", 0.2 } }, est = 27 },
                { s = { { "c", 0.2 } }, est = 27 },
            })
            assert.are.same({ "flash a>b credit 1" }, kinds(flicker.ledger(f, O)))
        end
    )

    it("records a retracted ready with no justifying event, its engine reason and the floor jitter flag", function()
        local f = build({
            { s = { { "x", 0.4, 40 } }, lo = 38, est = 41, hi = 44, truth = 41 },
            { s = { { "x", 0.0, 40 } }, lo = 40, est = 41, hi = 44, truth = 41 },
            { s = { { "x", 1.1, 40 } }, lo = 39, est = 41, hi = 44, truth = 41 }, -- lo cut by an answer, est steady
            { s = { { "x", 0.9, 40 } }, lo = 39, est = 41, hi = 44, truth = 41 },
            { s = { { "x", 0.0, 40 } }, lo = 40, est = 41, hi = 44, truth = 41 },
        })
        local led = flicker.ledger(f, O)
        local e = led.entries[1]
        assert.are.same(
            { "retracted", "x", 2, 3, 2, "usability", "cost", false, true },
            { e.kind, e.from, e.ready, e.tick, e.len, e.cause, e.reason, e.justified, e.floor }
        )
        assert.are.same({ -2, -2 }, { e.lo - e.truth, led.gapLo[#led.gapLo] }) -- lo-truth at the flip
        -- the same flip with our cast between the polls: justified (not the floor's count)
        f.ev.cast[3] = true
        e = flicker.ledger(f, O).entries[1]
        assert.are.same({ "retracted", "press", true }, { e.kind, e.cause, e.justified })
    end)

    it("records a wait oscillation: the same icon's wait jumping more than one poll, with no event", function()
        local f = build({
            { s = { { "x", 0.5 } } },
            { s = { { "x", 0.3 } } },
            { s = { { "x", 0.1 } } },
            { s = { { "x", 1.7 } }, ev = { swing = true } }, -- the countdown hit the swing and jumped to the next one
            { s = { { "x", 1.5 } } },
        })
        assert.are.same({ "wait x>x swing 1" }, kinds(flicker.ledger(f, O)))
        -- a pending swing ended with no credit (GAP AK's forecast taken back): a provisional credit vetoed
        f.pend[3], f.ev.swing[4] = true, false
        assert.are.same({ "wait x>x credit 1" }, kinds(flicker.ledger(f, O)))
    end)

    it("counts every displayed slot, the focus entry too, and a cooldown re-learned longer", function()
        local f = build({
            { s = { { "a", 0 }, {}, {}, { "x", 0.6 } }, cd = { x = 0.6 } },
            { s = { { "a", 0 }, {}, {}, { "x", 0.4 } }, cd = { x = 0.4 } },
            { s = { { "a", 0 }, {}, {}, { "x", 3.0 } }, cd = { x = 3.0 } },
        })
        local e = flicker.ledger(f, O).entries[1]
        assert.are.same({ "wait", 4, "cooldown" }, { e.kind, e.slot, e.cause })
    end)

    it("the decision gaps: lo-truth and est-truth where the first icon's cost lies in the band", function()
        local f = build({
            { s = { { "x", 0.3, 40 } }, lo = 37, est = 39, hi = 42, truth = 40 },
            { s = { { "x", 0.3, 40 } }, lo = 41, est = 42, hi = 43, truth = 42 }, -- lo above the cost: not gated
        })
        local led = flicker.ledger(f, O)
        assert.are.same({ { -3 }, { -1 } }, { led.gapLo, led.gapEst })
    end)

    it("summarises per minute, leaves our own presses out, and prints the line's fields", function()
        local f = build({
            { s = { { "a", 0 }, { "b", 0.3 } } },
            { s = { { "b", 0 }, { "a", 0.1 } }, ev = { cast = true } }, -- the press moved the queue on: justified
            { s = { { "a", 0 }, { "b", 0.1 } } },
            { s = { { "b", 0.1 }, { "a", 0.2 } } },
            { s = { { "a", 0 }, { "b", 0.2 } } },
        })
        local agg = flicker.merge(nil, flicker.ledger(f, O))
        local s = flicker.summary(agg, 1)
        assert.are.same({ 2, 0, 0 }, { s.dips, s.flashes, s.retracted })
        local line = flicker.line(s, flicker.summary(flicker.merge(nil, flicker.ledger(build({}), O)), 1))
        assert.is_truthy(line:find("dips 2.00 flashes 0.00; top [near-tie 2]; p90 length 1 ticks", 1, true), line)
        assert.is_truthy(line:find("retracted 0.00/min (oracle 0.00)", 1, true), line)
    end)
end)

describe("the display-side hold (o.hold)", function()
    local function q(name, time)
        return { name = { name, false, false, false }, time = { time, 0, 0, 0 }, cost = { 0, 0, 0, 0 } }
    end
    local function shown(h, seq, casts)
        local out = {}
        for i, x in ipairs(seq) do
            local qq = q(x[1], x[2])
            flicker.hold(h, qq, REACT, casts and casts[i])
            out[i] = qq.name[1] .. (qq.time[1] <= REACT and "!" or "")
        end
        return out
    end

    it("holds a change one poll: a one-poll dip never shows, a newly ready icon shows ready a poll late", function()
        local seq = { { "a", 0.4 }, { "b", 0 }, { "a", 0.2 }, { "a", 0 }, { "a", 0 } }
        assert.are.same({ "a", "a", "a", "a", "a!" }, shown(flicker.newHold(), seq))
    end)

    it("shows a retraction at once, and a change after our own cast unheld", function()
        local seq = { { "x", 0 }, { "x", 0 }, { "x", 0.6 }, { "y", 0 } }
        assert.are.same({ "x!", "x!", "x", "y!" }, shown(flicker.newHold(), seq, { false, false, false, true }))
    end)

    it("removes a one-poll retracted ready from the shown slot", function()
        local seq = { { "x", 0.4 }, { "x", 0 }, { "x", 0.6 }, { "x", 0.4 } }
        assert.are.same({ "x", "x", "x", "x" }, shown(flicker.newHold(), seq))
    end)
end)
