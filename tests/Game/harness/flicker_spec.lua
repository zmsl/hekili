-- tests/Game/harness/flicker_spec.lua: the flicker ledger (kinds, cause classes, the summary line) and the display-side
-- hold switch, on synthetic per-tick frames (class-neutral: abilities a, b, c, x).
local flicker = require("Game.harness.flicker")

local TICK, REACT = 0.2, 0.05

-- rows: { s = { { name, wait, cost }, ... (slots 1-4) }, lo, est, hi, truth, pend, cd = { [name] = s }, ev = { cast = true },
-- band = { lo, hi } }
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
        if r.band then -- the power band the belief applied (flicker.frame's bLo/bHi)
            f.bLo[n], f.bHi[n] = r.band[1], r.band[2]
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
        -- the belief's delta between the two polls
        assert.are.same(
            { 40, 39, 41, 41, false, false, false, false },
            { e.loP, e.loC, e.estP, e.estC, e.pendP, e.pendC, e.cdP, e.cdC }
        )
        -- the same flip with our cast between the polls: justified (not the floor's count)
        f.ev.cast[3] = true
        e = flicker.ledger(f, O).entries[1]
        assert.are.same({ "retracted", "press", true }, { e.kind, e.cause, e.justified })
    end)

    it("gives a retraction's engine reason: a cooldown learned longer, the GCD; and a near-tie re-ranked", function()
        local function one(rows)
            local e = flicker.ledger(build(rows), O).entries[1]
            return { e.kind, e.cause, e.reason, e.cdP, e.cdC }
        end
        assert.are.same(
            { "retracted", "cooldown", "cooldown", 0, 5 },
            one({
                { s = { { "x", 0.4 } }, cd = { x = 0.4 } },
                { s = { { "x", 0 } }, cd = { x = 0 } },
                { s = { { "x", 5 } }, cd = { x = 5 } }, -- a restart the belief learned: no cast of ours
            })
        )
        assert.are.same(
            { "retracted", "unknown", "gcd", false, false },
            one({
                { s = { { "x", 0.4 } } },
                { s = { { "x", 0 } } },
                { s = { { "x", 1.2 } }, gcd = 1.2 },
            })
        )
        assert.are.same(
            { "retracted", "near-tie", "condition", false, false },
            one({
                { s = { { "x", 0.4 }, { "y", 0.5 } } },
                { s = { { "x", 0 }, { "y", 0.1 } } }, -- y within a poll of x's ready
                { s = { { "x", 0.3 }, { "y", 0 } } },
            })
        )
    end)

    it("reads a cooldown stalled one poll at its end (the not-ready flag's probe) as the flash's cause", function()
        local function cause(cds)
            return kinds(flicker.ledger(
                build({
                    { s = { { "x", 0.5 } }, cd = { x = cds[1] } },
                    { s = { { "x", 0.5 } }, cd = { x = cds[2] } },
                    { s = { { "y", 0.1 } }, cd = { x = cds[3] } },
                    { s = { { "x", 0 } }, cd = { x = 0 } },
                    { s = { { "x", 0 } }, cd = { x = 0 } },
                }),
                O
            ))
        end
        assert.are.same({ "dip x>y cooldown 1" }, cause({ 0.5, 0.5, 0.5 })) -- 0.5 held where 0.3 was due: one tick off
        assert.are.same({ "dip x>y unknown 1" }, cause({ 0.5, 0.3, 0.1 })) -- a true countdown is no cooldown cause
    end)

    it("records an icon appearing in an empty slot and leaving as a flash, not a dip of the empty slot", function()
        local f = build({
            { s = { { "a", 0 } } },
            { s = { { "a", 0 }, { "b", 0.4 } } },
            { s = { { "a", 0 } } },
            { s = { { "a", 0 } } },
        })
        assert.are.same({ "flash false>b unknown 1" }, kinds(flicker.ledger(f, O)))
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

-- The jitter rule (L1762): the gate reads slot 1 (the now icon) and its now<->next swaps; slots 2-3 and the focus are
-- reported; a fact (a press, an avoid, an aura edge, a death or retarget, a late-found miss) justifies a change.
describe("the jitter rule's now slot (L1762)", function()
    local V = { tick = TICK, react = REACT, viewer = true } -- a Cooldown Manager arm: late lights, the verdict
    local function sum(rows, o)
        return flicker.summary(flicker.merge(nil, flicker.ledger(build(rows), o or O)), 1)
    end

    it(
        "gates slot 1 and tags a now<->next swap; slot 2's mirror is reported; the all-slot numbers unchanged",
        function()
            local s = sum({
                { s = { { "a", 0 }, { "b", 0.3 } } },
                { s = { { "b", 0 }, { "a", 0.1 } }, ev = { cast = true } },
                { s = { { "a", 0 }, { "b", 0.1 } } },
                { s = { { "b", 0.1 }, { "a", 0.2 } } }, -- a swap with no fact: slot 1's dip (gated), slot 2's (reported)
                { s = { { "a", 0 }, { "b", 0.2 } } },
            })
            assert.are.same({ 2, 0, 0 }, { s.dips, s.flashes, s.retracted }) -- the old all-slot numbers
            assert.are.same({ 1, 0, 1, 0, 0 }, { s.now.dips, s.now.flashes, s.now.swaps, s.now.retracted, s.now.waits })
            assert.are.same({ 1, 0 }, { s.next.dips, s.next.flashes })
            local line = flicker.line(s, s)
            assert.is_truthy(
                line:find("; now dips 1.00 flashes 0.00 swaps 1.00 retracted 0.00/min (oracle 0.00)", 1, true),
                line
            )
        end
    )

    it("reports a retracted ready in slots 2-3 or the focus, gates one in slot 1", function()
        local function rows(slot)
            local function at(w)
                local q = { { "a", 0.4 } }
                q[slot] = { "x", w }
                return { s = q }
            end
            return { at(0.4), at(0), at(1.1), at(0.9), at(0) }
        end
        local s2, s4 = sum(rows(2)), sum(rows(4))
        assert.are.same({ 0, 1 }, { s2.now.retracted, s2.next.retracted })
        assert.are.same({ 0, 1 }, { s4.now.retracted, s4.focus.retracted })
        assert.are.same({ 1, 1 }, { s2.retracted, s4.retracted }) -- the old all-slot count keeps both
        assert.are.equal(1, sum(rows(1)).now.retracted)
    end)

    it("justifies a change at a death or retarget, and (viewer on) at an aura edge one poll before it", function()
        local function dip(ev, o)
            local r = {
                { s = { { "a", 0.4 } } },
                { s = { { "a", 0.2 } } },
                { s = { { "b", 0.1 } } }, -- the dip's start, poll 3
                { s = { { "a", 0 } } },
                { s = { { "a", 0 } } },
            }
            for k, at in pairs(ev) do
                r[at].ev = r[at].ev or {}
                r[at].ev[k] = true
            end
            return sum(r, o)
        end
        assert.are.same({ 1, nil }, { dip({}).now.dips, dip({}).facts.target })
        local t, a, early = dip({ target = 3 }), dip({ aura = 2 }, V), dip({ aura = 1 }, V)
        assert.are.same({ 0, 1, 1 }, { t.now.dips, t.facts.target, t.dips }) -- the old count keeps it
        assert.are.same({ 0, 1 }, { a.now.dips, a.facts.aura })
        assert.are.equal(1, early.now.dips) -- two polls before: no longer the change's fact
        assert.are.same({ 1, nil }, { dip({ aura = 2 }).now.dips, dip({ aura = 2 }).facts.aura }) -- no viewer: no late light
        assert.are.same({ 0, 1 }, { dip({ aura = 3 }).now.dips, dip({ aura = 3 }).dips }) -- at the change: the aura class
    end)

    it("justifies the first change within the late window after a miss of our press (the CDM verdict)", function()
        local rows = {}
        for i = 1, 20 do
            rows[i] = { s = { { "a", 0.4 } } }
        end
        rows[2].ev = { miss = true, cast = true } -- our press's avoid row (the miss), at its cast
        for _, i in ipairs({ 6, 8, 16 }) do -- three one-poll dips: 4 and 6 polls on (in the window), 14 on (past it)
            rows[i] = { s = { { "b", 0.1 } } }
        end
        local s = sum(rows, V)
        assert.are.same({ 2, 1, 3 }, { s.now.dips, s.facts.verdict, s.dips }) -- only the first one is the correction
        local led = flicker.ledger(build(rows), V)
        assert.are.same({ true, "verdict" }, { led.entries[1].justified, led.entries[1].fact })
        assert.are.same({ 3, nil }, { sum(rows).now.dips, sum(rows).facts.verdict }) -- no viewer: no verdict
    end)

    it(
        "does not excuse a retraction by the fact that made the icon ready (an aura edge at its first ready poll)",
        function()
            local rows = {
                { s = { { "x", 0.4 } } },
                { s = { { "x", 0 } }, ev = { aura = true } }, -- a proc shows x ready
                { s = { { "x", 1.1 } } }, -- taken back with no fact
                { s = { { "x", 0.9 } } },
            }
            assert.are.same({ 1, 1 }, { sum(rows).now.retracted, sum(rows).retracted })
            rows[3].ev = { target = true } -- a retarget in the ready run: a correction
            assert.are.same({ 0, 1 }, { sum(rows).now.retracted, sum(rows).retracted })
        end
    )

    it("an avoid row with no cast (a builder's lost combo point, an energy refund) justifies its change", function()
        local s = sum({
            { s = { { "a", 0.4 } } },
            { s = { { "b", 0 } }, ev = { avoid = true } },
            { s = { { "a", 0 } } },
            { s = { { "a", 0 } } },
        })
        assert.are.same({ 0, 1 }, { s.now.dips, s.dips })
    end)
end)

describe("the jitter rule on the gated flicker (flicker.changes, loop.flips, L1762 round 2)", function()
    local loop = require("Game.harness.loop")
    local V = { tick = TICK, react = REACT, viewer = true }
    -- a one-poll flip a,b,a at polls 3, 4, 5 (the change at 4, the return at 5); `mod` sets events and the belief's
    -- power band by poll: { [poll] = { ev = {...}, band = { lo, hi }, lo = x (lo = est = hi) } }
    local function flip(mod, o)
        local rows = {}
        for i, x in ipairs({ "a", "a", "a", "b", "a", "a" }) do
            rows[i] = { s = { { x, 0.2 } } }
            for k, v in pairs(mod and mod[i] or {}) do
                rows[i][k] = v
            end
        end
        local f = build(rows)
        local seq = {}
        for i = 1, f.n do
            seq[i] = f.name[1][i]
        end
        local why, by = flicker.changes(f, o or O), {}
        return loop.flips(seq, f.n, nil, why, by), why, by, loop.flips(seq, f.n)
    end

    it("counts a flip whose change has no fact; the old press-only count reads the same", function()
        local n, why, _, old = flip()
        assert.are.same({ 1, false, 1 }, { n, why[4], old })
    end)

    it("excuses a flip whose change follows a fact at its poll: press, avoid, aura edge, death or retarget", function()
        for _, k in ipairs({ "cast", "spend", "avoid", "aura", "target" }) do
            local n, why, by, old = flip({ [4] = { ev = { [k] = true } } })
            local name = (k == "cast" or k == "spend") and "press" or k
            assert.are.same({ 0, name, 1, 1 }, { n, why[4], by[name], old }, k)
        end
        assert.are.equal(1, (flip({ [3] = { ev = { aura = true } } }))) -- a poll before, no viewer: not this change's
        assert.are.equal(1, (flip({ [5] = { ev = { aura = true } } }))) -- the return's fact alone: the change had none
    end)

    it(
        "excuses, with the Cooldown Manager on only, the late light and the verdict after a miss of our press",
        function()
            local late = { [3] = { ev = { aura = true } } }
            assert.are.same({ 0, "aura" }, { flip(late, V), select(2, flip(late, V))[4] })
            local miss = { [1] = { ev = { miss = true, cast = true } } } -- our press's avoid row, 3 polls before the change
            assert.are.same({ 0, "verdict" }, { flip(miss, V), select(2, flip(miss, V))[4] })
            assert.are.same({ 1, 1 }, { flip(late), (flip(miss)) }) -- the default arm: neither
        end
    )

    it("excuses a crossing of the belief's power band that the belief follows", function()
        local n, why = flip({ [3] = { band = { 15, 16 } }, [4] = { band = { 20, 21 }, lo = 20 } })
        assert.are.same({ 0, "band" }, { n, why[4] })
        -- the same band at both polls (a re-assert) is no crossing
        assert.are.equal(1, (flip({ [3] = { band = { 20, 21 }, lo = 20 }, [4] = { band = { 20, 21 }, lo = 20 } })))
    end)

    it("does not excuse a change that follows a stale answer, older than the band crossing at its poll", function()
        -- B4 round 4's class A: the band crosses to 33-34, the belief sits at 29.99 (a short answer from before it)
        local A = { [3] = { band = { 28, 29 } }, [4] = { band = { 33, 34 }, lo = 29.99, ev = { avoid = true } } }
        local n, why = flip(A)
        assert.are.same({ 1, "stale" }, { n, why[4] }) -- the avoid at that poll does not excuse it either
        A[4].ev = { cast = true } -- our own press: a spend after the band's stamp puts the belief under it
        assert.are.equal(0, (flip(A)))
        -- class B: the change follows an aura edge, the return a stale answer under the next crossing
        local B = { [4] = { ev = { aura = true }, band = { 9, 10 }, lo = 9 }, [5] = { band = { 17, 18 }, lo = 9.99 } }
        n, why = flip(B)
        assert.are.same({ 1, "aura", "stale" }, { n, why[4], why[5] })
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
