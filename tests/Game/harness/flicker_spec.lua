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
                { s = { { "a", 0 }, { "b", 0.1 } }, ev = { cast = true } }, -- the return on its own press (L1791)
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
                { s = { { "a", 0 } }, ev = { cast = true } }, -- the return, on our press (L1791: its own fact)
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
        for _, i in ipairs({ 7, 9, 17 }) do -- each return on our press (L1791: its own fact)
            rows[i].ev = { cast = true }
        end
        local s = sum(rows, V)
        assert.are.same({ 2, 1, 3 }, { s.now.dips, s.facts.verdict, s.dips }) -- only the first one is the correction
        local led = flicker.ledger(build(rows), V)
        assert.are.same({ true, "verdict" }, { led.entries[1].justified, led.entries[1].fact })
        assert.are.same({ 3, nil }, { sum(rows).now.dips, sum(rows).facts.verdict }) -- no viewer: no verdict
    end)

    it("counts a dip whose return follows no fact of its own, the change's late light included (L1791)", function()
        local function dip(ev, o)
            local r = {
                { s = { { "a", 0.4 } } },
                { s = { { "a", 0.2 } } },
                { s = { { "b", 0.1 } } }, -- the change, poll 3
                { s = { { "a", 0 } } }, -- the return, poll 4
                { s = { { "a", 0 } } },
            }
            for at, e in pairs(ev) do
                r[at].ev = e
            end
            return sum(r, o)
        end
        local t = dip({ [3] = { target = true } })
        assert.are.same({ 1, 1, nil }, { t.now.dips, t.dips, t.facts.target }) -- the return has no fact
        assert.are.same({ 0, 1 }, { dip({ [3] = { target = true }, [4] = { avoid = true } }).now.dips, t.dips })
        -- the viewer's late light at the return is the change's own aura edge, not a new fact; a second edge is one
        assert.are.equal(1, dip({ [3] = { aura = true } }, V).now.dips)
        assert.are.equal(0, dip({ [3] = { aura = true }, [4] = { aura = true } }, V).now.dips)
        -- the change on our press: the edge at that poll is the return's own (its light lands at the return)
        assert.are.equal(0, dip({ [3] = { aura = true, cast = true } }, V).now.dips)
        -- the verdict as the return's fact: a miss of our press found late, the return within the window
        local rows = {}
        for i = 1, 8 do
            rows[i] = { s = { { "a", 0.4 } } }
        end
        rows[2].ev = { miss = true, cast = true }
        rows[5] = { s = { { "b", 0.1 } }, ev = { target = true } }
        local s = sum(rows, V)
        assert.are.same({ 0, 1, nil }, { s.now.dips, s.facts.target, s.facts.verdict }) -- by the change's
        local e = flicker.ledger(build(rows), V).entries[1]
        assert.are.same({ "target", "verdict", true }, { e.fact, e.back, e.justified })
    end)

    it("fills one poll per verdict: the dip's change, or its return when the change came before the miss", function()
        local function rows(mod)
            local r = {}
            for i = 1, 10 do
                r[i] = { s = { { "a", 0.4 } } }
            end
            for i, x in pairs(mod) do
                r[i] = x
            end
            return r
        end
        -- one miss, a dip with no fact at either poll: the verdict is the change's, the return still counts
        local one =
            rows({ [2] = { s = { { "a", 0.4 } }, ev = { miss = true, cast = true } }, [5] = { s = { { "b", 0.1 } } } })
        local e = flicker.ledger(build(one), V).entries[1]
        assert.are.same({ 1, "verdict", nil, false }, { sum(one, V).now.dips, e.fact, e.back, e.justified })
        -- the change on a retarget before the miss, the return after it: the verdict is the return's
        local before = rows({
            [3] = { s = { { "b", 0.1 } }, ev = { target = true } },
            [4] = { s = { { "b", 0.1 } }, ev = { miss = true, cast = true } },
        })
        e = flicker.ledger(build(before), V).entries[1]
        assert.are.same({ 0, "target", "verdict" }, { sum(before, V).now.dips, e.fact, e.back })
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
            { s = { { "a", 0 } }, ev = { avoid = true } }, -- the return on its own avoid row (L1791)
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

    -- the jitter rule's return (L1791, the owner 2026-11-23: "new facts are always required"): the change to b and the
    -- return to a each follow their own new fact
    it("counts a flip whose change follows a fact but whose return follows none (L1791)", function()
        for _, k in ipairs({ "press", "outcome", "aura", "target" }) do
            local n, why = flip({ [4] = { ev = { [k] = true } } })
            assert.are.same({ 1, k == "outcome" and "avoid" or k, false }, { n, why[4], why[5] }, k)
        end
        -- the return's fact alone: the change had none
        assert.are.equal(1, (flip({ [5] = { ev = { aura = true } } })))
    end)

    it(
        "excuses a flip whose change and return each follow a fact: press, avoid, aura edge, death or retarget",
        function()
            for _, k in ipairs({ "press", "outcome", "aura", "target" }) do
                local n, why, by, old = flip({ [4] = { ev = { [k] = true } }, [5] = { ev = { press = true } } })
                local name = k == "outcome" and "avoid" or k
                assert.are.same({ 0, name, "press", 1, 1 }, { n, why[4], why[5], by[name], old }, k)
            end
            -- a ranged auto shot's cast or avoid row alone (cast / avoid without press / outcome: loop.lua) is no fact
            local back = { ev = { press = true } }
            assert.are.same({ 1, 1 }, {
                flip({ [4] = { ev = { cast = true } }, [5] = back }),
                (flip({ [4] = { ev = { avoid = true } }, [5] = back })),
            })
            assert.are.equal(1, (flip({ [3] = { ev = { aura = true } }, [5] = back }))) -- a poll before, no viewer
        end
    )

    it("does not take the late light of the change's own aura edge as the return's fact (viewer on)", function()
        local one = { [4] = { ev = { aura = true } } } -- one edge at the change: its light reaches the return poll
        local n, why = flip(one, V)
        assert.are.same({ 1, "aura", false }, { n, why[4], why[5] })
        local two = { [4] = { ev = { aura = true } }, [5] = { ev = { aura = true } } } -- a second edge: a new fact
        n, why = flip(two, V)
        assert.are.same({ 0, "aura", "aura" }, { n, why[4], why[5] })
        -- the change followed our press, not the edge: the edge's late light is the return's own
        n, why = flip({ [4] = { ev = { aura = true, press = true } } }, V)
        assert.are.same({ 0, "press", "aura" }, { n, why[4], why[5] })
    end)

    it(
        "excuses, with the Cooldown Manager on only, the late light and the verdict after a miss of our press",
        function()
            local back = { ev = { press = true } }
            local late = { [3] = { ev = { aura = true } }, [5] = back }
            assert.are.same({ 0, "aura" }, { flip(late, V), select(2, flip(late, V))[4] })
            local miss = { [1] = { ev = { miss = true, cast = true } }, [5] = back } -- our press's avoid row, 3 polls on
            assert.are.same({ 0, "verdict" }, { flip(miss, V), select(2, flip(miss, V))[4] })
            assert.are.same({ 1, 1 }, { flip(late), (flip(miss)) }) -- the default arm: neither
            -- the verdict as the return's fact: the change on an aura edge, the miss found late at the return
            local ret = { [2] = { ev = { miss = true, cast = true } }, [4] = { ev = { aura = true } } }
            local n, why = flip(ret, V)
            assert.are.same({ 0, "aura", "verdict" }, { n, why[4], why[5] })
        end
    )

    it("takes one miss of our press as one fact: its verdict excuses the change, not the return as well", function()
        local n, why = flip({ [3] = { ev = { miss = true, cast = true } } }, V)
        assert.are.same({ 1, "verdict", false }, { n, why[4], why[5] })
    end)

    it("excuses a crossing of the belief's power band that the belief follows", function()
        local up = { [3] = { band = { 15, 16 } }, [4] = { band = { 20, 21 }, lo = 20 } }
        up[5] = { band = { 25, 26 }, lo = 25 } -- the return on a second crossing
        local n, why = flip(up)
        assert.are.same({ 0, "band", "band" }, { n, why[4], why[5] })
        up[5] = { band = { 20, 21 }, lo = 20 } -- the same band at the return (a re-assert) is no crossing
        assert.are.equal(1, (flip(up)))
    end)

    it("does not excuse a change that follows a stale answer, older than the band crossing at its poll", function()
        -- B4 round 4's class A: the band crosses to 33-34, the belief sits at 29.99 (a short answer from before it)
        local A = { [3] = { band = { 28, 29 } }, [4] = { band = { 33, 34 }, lo = 29.99, ev = { outcome = true } } }
        A[5] = { band = { 33, 34 }, lo = 29.99, ev = { press = true } }
        local n, why = flip(A)
        assert.are.same({ 1, "stale" }, { n, why[4] }) -- the avoid at that poll does not excuse it either
        A[4].ev = { press = true } -- our own press: a spend after the band's stamp puts the belief under it
        assert.are.equal(0, (flip(A)))
    end)

    it("counts a stale return, even after a change on a fact and with another fact at the return (L1791)", function()
        -- class B: the change follows an aura edge, the return a stale answer under the next crossing
        local B = { [4] = { ev = { aura = true }, band = { 9, 10 }, lo = 9 }, [5] = { band = { 17, 18 }, lo = 9.99 } }
        local n, why = flip(B)
        assert.are.same({ 1, "aura", "stale" }, { n, why[4], why[5] })
        B[5].ev = { outcome = true, target = true } -- an avoid and a retarget at the stale poll: vetoed
        n, why = flip(B)
        assert.are.same({ 1, "stale" }, { n, why[5] })
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
