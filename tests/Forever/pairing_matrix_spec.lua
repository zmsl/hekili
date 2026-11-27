-- tests/Forever/pairing_matrix_spec.lua (refactor plan lane 2, L1827): the pairing matrix. Every case of
-- finisher_miss_spec.lua (a missed or landed Rip or Rake, its own row or none, a white swing's row near it, secret or
-- plain amounts, a Cooldown Manager item or none) as one row: the event sequence (the case's knobs, built on the scenario
-- builder through helpers/finisher_world.lua) and the outcome today's code gives it, pinned as literals. Lane 9 (Pr-2,
-- the claim record) must keep every row identical while route's rules move into a table.
-- The columns, read after the case's run (T: the case's cast):
--   route   the belief's emitted miss and hit rows near T (SPELL_MISSED / SPELL_DAMAGE: the cast took the row;
--           SWING_MISSED: the swing did; none: no row was paid), each at its stamp from T;
--   undo    the believed bleed's first SPELL_AURA_REMOVED from T (the record undone), "-" none;
--   avoids  I.avoidsRun at the end: the avoided-cast reactions that ran (the undo and refund path; a Cooldown Manager
--           light since the cast still drops the refund after it, F4b, so 1 here is not always a refund paid);
--   verdict finisher_world's check: "pass", or its first failure (finisher_miss_spec's pinned windows);
--   back    slot 1's first return to the bleed and the last wrong icon's publish, s from T ("-" none).
-- The research counted 57 cases (2026-11-23); the spec had 60 at its commit then (743b76463) and has 65 today: the five
-- "P" rows are the combo point fact's (lane cp-fact, L1832), added after the count. All 65 are pinned.
-- #pin: green on the base by design (tools/red_first.sh). A change that moves a row on purpose re-pins it: run with
-- MATRIX_CAPTURE=<file> and the spec appends every row's actual columns there.
local fw = require("Forever.helpers.finisher_world")

local PT_AVOID = 0.3 -- finisher_miss_spec's: a missed builder's information time is the point that never came (L1832)
local TIE = -0.471 -- finisher_miss_spec's: a swing whose row lands 3 ms after the success (its core band)

-- One case as finisher_miss_spec's run() runs it; returns the row's columns.
local function outcome(knobs)
    local c = {}
    for k, v in pairs(knobs) do
        c[k] = v
    end
    c.rows = true
    if c.bleed == "rake" and c.act ~= "WOUND" and not c.pointFact then
        c.pointFact = PT_AVOID
        c.info = c.info or math.max(PT_AVOID, c.row or 0)
    end
    local W, T = fw.case(c)
    if c.windowW then
        c.window = W.verdictW
    end
    local fails, sum = fw.check(W, T, c)
    assert.are.same({}, W.H.errors)
    local route, undo = {}, "-"
    for _, row in ipairs(W.rows) do
        local d = row[4] - T
        if d > -0.6 and d < 3 then
            if row[1] == "SPELL_MISSED" or row[1] == "SPELL_DAMAGE" then
                route[#route + 1] = ("%s %s %+.3f"):format(row[1], tostring(row[3]), d)
            elseif row[1] == "SWING_MISSED" then
                route[#route + 1] = ("%s %s %+.3f"):format(row[1], tostring(row[2]), d)
            elseif row[1] == "SPELL_AURA_REMOVED" and undo == "-" then
                undo = ("%+.3f"):format(d)
            end
        end
    end
    local function s(v)
        return v and ("%.3f"):format(v) or "-"
    end
    return table.concat(route, "; "), undo, W.I.avoidsRun, fails[1] or "pass", s(sum.back) .. " " .. s(sum.wrongLast)
end

-- { name, knobs, route, undo, avoids, verdict, back }. Names: 1-5 finisher_miss_spec's ways a miss reaches the belief,
-- C the controls, M the mirror (a landed Rip, our swing's avoid in its window), P the combo point fact.
local MATRIX = {
    {
        "1 Rip MISS own row +4 ms",
        { act = "MISS", bleed = "rip", row = 0.004 },
        "SPELL_MISSED MISS +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "2 Rip MISS row -15 ms (fix A)",
        { act = "MISS", bleed = "rip", row = -0.015 },
        "SPELL_MISSED MISS +0.000",
        "+0.000",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip MISS swing frame, secret",
        { act = "MISS", bleed = "rip", row = 0.004, swingAt = TIE },
        "SPELL_MISSED MISS +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip MISS swing frame, secret, viewer",
        { act = "MISS", bleed = "rip", row = 0.004, swingAt = TIE, viewer = "proven", windowW = true },
        "SPELL_MISSED MISS +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip MISS swing frame, plain",
        { act = "MISS", bleed = "rip", plain = true, row = 0.004, swingAt = TIE },
        "SPELL_MISSED MISS +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3b Rip MISS swing -16 ms (SAME_FRAME)",
        { act = "MISS", bleed = "rip", row = 0.004, swingAt = -0.016 },
        "SPELL_MISSED MISS +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "4 Rip MISS no row, viewer dark",
        { act = "MISS", bleed = "rip", viewer = "proven", windowW = true },
        "",
        "-",
        0,
        "pass",
        "0.583 0.367",
    },
    {
        "1 Rip DODGE own row +4 ms",
        { act = "DODGE", bleed = "rip", row = 0.004 },
        "SPELL_MISSED DODGE +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "2 Rip DODGE row -15 ms (fix A)",
        { act = "DODGE", bleed = "rip", row = -0.015 },
        "SPELL_MISSED DODGE +0.000",
        "+0.000",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip DODGE swing frame, secret",
        { act = "DODGE", bleed = "rip", row = 0.004, swingAt = TIE },
        "SPELL_MISSED DODGE +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip DODGE swing frame, secret, viewer",
        { act = "DODGE", bleed = "rip", row = 0.004, swingAt = TIE, viewer = "proven", windowW = true },
        "SPELL_MISSED DODGE +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip DODGE swing frame, plain",
        { act = "DODGE", bleed = "rip", plain = true, row = 0.004, swingAt = TIE },
        "SPELL_MISSED DODGE +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3b Rip DODGE swing -16 ms (SAME_FRAME)",
        { act = "DODGE", bleed = "rip", row = 0.004, swingAt = -0.016 },
        "SPELL_MISSED DODGE +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "4 Rip DODGE no row, viewer dark",
        { act = "DODGE", bleed = "rip", viewer = "proven", windowW = true },
        "",
        "-",
        0,
        "pass",
        "0.583 0.367",
    },
    {
        "1 Rip PARRY own row +4 ms",
        { act = "PARRY", bleed = "rip", row = 0.004 },
        "SPELL_MISSED PARRY +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "2 Rip PARRY row -15 ms (fix A)",
        { act = "PARRY", bleed = "rip", row = -0.015 },
        "SPELL_MISSED PARRY +0.000",
        "+0.000",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip PARRY swing frame, secret",
        { act = "PARRY", bleed = "rip", row = 0.004, swingAt = TIE },
        "SPELL_MISSED PARRY +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip PARRY swing frame, secret, viewer",
        { act = "PARRY", bleed = "rip", row = 0.004, swingAt = TIE, viewer = "proven", windowW = true },
        "SPELL_MISSED PARRY +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rip PARRY swing frame, plain",
        { act = "PARRY", bleed = "rip", plain = true, row = 0.004, swingAt = TIE },
        "SPELL_MISSED PARRY +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3b Rip PARRY swing -16 ms (SAME_FRAME)",
        { act = "PARRY", bleed = "rip", row = 0.004, swingAt = -0.016 },
        "SPELL_MISSED PARRY +0.000",
        "+0.004",
        1,
        "pass",
        "0.150 -",
    },
    {
        "4 Rip PARRY no row, viewer dark",
        { act = "PARRY", bleed = "rip", viewer = "proven", windowW = true },
        "",
        "-",
        0,
        "pass",
        "0.583 0.367",
    },
    {
        "5 Rip DODGE no row, cdmOff",
        { act = "DODGE", bleed = "rip", cdmOff = true, span = 13, viewer = "proven" },
        "",
        "-",
        0,
        "+0.150 slot 1 shows ferocious_bite while rip is down",
        "12.117 8.633",
    },
    {
        "5 Rip DODGE no row, not tracked",
        { act = "DODGE", bleed = "rip", span = 13 },
        "",
        "-",
        0,
        "+0.150 slot 1 shows ferocious_bite while rip is down",
        "12.117 8.633",
    },
    {
        "1 Rake MISS own row +4 ms",
        { act = "MISS", bleed = "rake", row = 0.004 },
        "SPELL_MISSED MISS +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "2 Rake MISS row -15 ms (fix A)",
        { act = "MISS", bleed = "rake", row = -0.015 },
        "SPELL_MISSED MISS +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake MISS swing frame, secret",
        { act = "MISS", bleed = "rake", row = 0.004, swingAt = TIE },
        "SPELL_MISSED MISS +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake MISS swing frame, secret, viewer",
        { act = "MISS", bleed = "rake", row = 0.004, swingAt = TIE, viewer = "proven", windowW = true },
        "SPELL_MISSED MISS +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake MISS swing frame, plain",
        { act = "MISS", bleed = "rake", plain = true, row = 0.004, swingAt = TIE, window = 0.25 },
        "SPELL_DAMAGE 60 +0.000; SWING_MISSED MISS -0.471",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "3b Rake MISS swing -16 ms (SAME_FRAME)",
        { act = "MISS", bleed = "rake", row = 0.004, swingAt = -0.016 },
        "SPELL_MISSED MISS +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "4 Rake MISS no row, viewer dark",
        { act = "MISS", bleed = "rake", viewer = "proven", windowW = true },
        "",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "1 Rake DODGE own row +4 ms",
        { act = "DODGE", bleed = "rake", row = 0.004 },
        "SPELL_MISSED DODGE +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "2 Rake DODGE row -15 ms (fix A)",
        { act = "DODGE", bleed = "rake", row = -0.015 },
        "SPELL_MISSED DODGE +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake DODGE swing frame, secret",
        { act = "DODGE", bleed = "rake", row = 0.004, swingAt = TIE },
        "SPELL_MISSED DODGE +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake DODGE swing frame, secret, viewer",
        { act = "DODGE", bleed = "rake", row = 0.004, swingAt = TIE, viewer = "proven", windowW = true },
        "SPELL_MISSED DODGE +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake DODGE swing frame, plain",
        { act = "DODGE", bleed = "rake", plain = true, row = 0.004, swingAt = TIE, window = 0.25 },
        "SPELL_DAMAGE 60 +0.000; SWING_MISSED DODGE -0.471",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "3b Rake DODGE swing -16 ms (SAME_FRAME)",
        { act = "DODGE", bleed = "rake", row = 0.004, swingAt = -0.016 },
        "SPELL_MISSED DODGE +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "4 Rake DODGE no row, viewer dark",
        { act = "DODGE", bleed = "rake", viewer = "proven", windowW = true },
        "",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "1 Rake PARRY own row +4 ms",
        { act = "PARRY", bleed = "rake", row = 0.004 },
        "SPELL_MISSED PARRY +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "2 Rake PARRY row -15 ms (fix A)",
        { act = "PARRY", bleed = "rake", row = -0.015 },
        "SPELL_MISSED PARRY +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake PARRY swing frame, secret",
        { act = "PARRY", bleed = "rake", row = 0.004, swingAt = TIE },
        "SPELL_MISSED PARRY +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake PARRY swing frame, secret, viewer",
        { act = "PARRY", bleed = "rake", row = 0.004, swingAt = TIE, viewer = "proven", windowW = true },
        "SPELL_MISSED PARRY +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "3 Rake PARRY swing frame, plain",
        { act = "PARRY", bleed = "rake", plain = true, row = 0.004, swingAt = TIE, window = 0.25 },
        "SPELL_DAMAGE 60 +0.000; SWING_MISSED PARRY -0.471",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "3b Rake PARRY swing -16 ms (SAME_FRAME)",
        { act = "PARRY", bleed = "rake", row = 0.004, swingAt = -0.016 },
        "SPELL_MISSED PARRY +0.000",
        "+0.367",
        1,
        "pass",
        "0.150 -",
    },
    {
        "4 Rake PARRY no row, viewer dark",
        { act = "PARRY", bleed = "rake", viewer = "proven", windowW = true },
        "",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "5 Rake DODGE no row, cdmOff",
        { act = "DODGE", bleed = "rake", cdmOff = true, span = 10, viewer = "proven" },
        "",
        "+0.367",
        1,
        "+0.367 slot 1 shows shred while rake is down",
        "0.583 0.367",
    },
    {
        "5 Rake DODGE no row, not tracked",
        { act = "DODGE", bleed = "rake", span = 10 },
        "",
        "+0.367",
        1,
        "+0.367 slot 1 shows shred while rake is down",
        "0.583 0.367",
    },
    -- the controls and the mirror
    {
        "C Rip lands",
        { act = "WOUND", expect = { { 0.004, "shred" }, { 1.5, "ferocious_bite" } }, pointsAt = { 1.5, 5 } },
        "",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "C Rake lands",
        { act = "WOUND", bleed = "rake", expect = { { 0.004, "shred" } }, row = 0.004 },
        "",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M seed 2, secret",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "DODGE", lag = 0.176 },
            pointsAt = { 1.5, 5 },
            swingAt = 0.335,
        },
        "",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M seed 2, plain",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "DODGE", lag = 0.176 },
            plain = true,
            pointsAt = { 1.5, 5 },
            swingAt = 0.335,
        },
        "SWING_MISSED DODGE +0.335",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M seed 8, secret",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "MISS", lag = 0.62 },
            pointsAt = { 1.5, 5 },
            swingAt = 0.005,
        },
        "SWING_MISSED MISS +0.005",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M seed 8, plain",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "MISS", lag = 0.62 },
            plain = true,
            pointsAt = { 1.5, 5 },
            swingAt = 0.005,
        },
        "SWING_MISSED MISS +0.005",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M core band, secret",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "MISS", lag = 0.474 },
            pointsAt = { 1.5, 5 },
            swingAt = TIE,
        },
        "SWING_MISSED MISS -0.471",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M core band, plain",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "MISS", lag = 0.474 },
            plain = true,
            pointsAt = { 1.5, 5 },
            swingAt = TIE,
        },
        "SWING_MISSED MISS -0.471",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M own ms, plain",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "MISS", lag = 0 },
            plain = true,
            pointsAt = { 1.5, 5 },
            swingAt = 0.011,
        },
        "SWING_MISSED MISS +0.011",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "M own ms, secret (PINNED)",
        { act = "WOUND", odd = { act = "MISS", lag = 0 }, pointsAt = { 1.5, 5 }, swingAt = 0.011 },
        "SPELL_MISSED MISS +0.000",
        "+0.011",
        1,
        "+0.050 the belief holds rip down, the truth the other",
        "- -",
    },
    {
        "M own ms, secret, viewer",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "MISS", lag = 0 },
            pointsAt = { 1.5, 5 },
            swingAt = 0.011,
            viewer = "proven",
        },
        "SPELL_MISSED MISS +0.000",
        "+0.011",
        1,
        "pass",
        "- -",
    },
    {
        "M tick, secret (PINNED)",
        { act = "WOUND", odd = { act = "MISS", lag = 0.474 }, pointsAt = { 1.5, 5 }, swingAt = TIE, tickAt = 0.002 },
        "SPELL_MISSED MISS +0.000",
        "+0.003",
        1,
        "+0.050 the belief holds rip down, the truth the other",
        "- -",
    },
    {
        "M tick, secret, viewer",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "MISS", lag = 0.474 },
            pointsAt = { 1.5, 5 },
            swingAt = TIE,
            tickAt = 0.002,
            viewer = "proven",
        },
        "SPELL_MISSED MISS +0.000",
        "+0.003",
        1,
        "pass",
        "- -",
    },
    {
        "M seed 2, plain, viewer",
        {
            act = "WOUND",
            expect = { { 1.5, "ferocious_bite" } },
            odd = { act = "DODGE", lag = 0.176 },
            plain = true,
            pointsAt = { 1.5, 5 },
            swingAt = 0.335,
            viewer = "proven",
        },
        "SWING_MISSED DODGE +0.335",
        "-",
        0,
        "pass",
        "- -",
    },
    -- the combo point fact (L1832): added after the research's count of 57
    {
        "P Rake lands, swing MISS core band",
        {
            act = "WOUND",
            bleed = "rake",
            expect = { { 0.004, "shred" } },
            odd = { act = "MISS", lag = 0.474 },
            row = 0.001,
            swingAt = -0.444,
        },
        "SPELL_MISSED MISS +0.000",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "P Rake lands, 2 points",
        {
            act = "WOUND",
            bleed = "rake",
            expect = { { 0.004, "shred" } },
            gain = 2,
            odd = { act = "MISS", lag = 0.474 },
            row = 0.001,
            swingAt = -0.444,
        },
        "SPELL_MISSED MISS +0.000",
        "-",
        0,
        "pass",
        "- -",
    },
    {
        "P Rake MISS tied to open swing",
        { act = "MISS", bleed = "rake", odd = { act = "MISS", lag = 1.2 }, row = 0.004, swingAt = TIE, window = 0.25 },
        "SWING_MISSED MISS -0.471",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "P Rake DODGE tied to open swing",
        { act = "DODGE", bleed = "rake", odd = { act = "MISS", lag = 1.2 }, row = 0.004, swingAt = TIE, window = 0.25 },
        "SWING_MISSED DODGE -0.471",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
    {
        "P Rake PARRY tied to open swing",
        { act = "PARRY", bleed = "rake", odd = { act = "MISS", lag = 1.2 }, row = 0.004, swingAt = TIE, window = 0.25 },
        "SWING_MISSED PARRY -0.471",
        "+0.367",
        1,
        "pass",
        "0.583 0.367",
    },
}

describe("the pairing matrix (finisher_miss_spec's cases, refactor lane 2) #pin", function()
    local capture = os.getenv("MATRIX_CAPTURE")
    for _, m in ipairs(MATRIX) do
        it(m[1], function()
            local route, undo, avoids, verdict, back = outcome(m[2])
            if capture then
                local out = assert(io.open(capture, "a"))
                out:write(("%q: %q, %q, %d, %q, %q\n"):format(m[1], route, undo, avoids, verdict, back))
                out:close()
            end
            assert.are.same({ m[3], m[4], m[5], m[6], m[7] }, { route, undo, avoids, verdict, back })
        end)
    end
end)

-- Lane 9 (Pr-2, the claim table, L1827): the rule that decided each row of each case. A row near the case's cast (as
-- the route column's window) reads "<stamp from T> <action> <rule>><rule>... =<owner>...": the rules that marked it in
-- order (Rows.lua's RULES, I.Rows.trace) and every ticket paid by it (cast, or swing and its hand). Pinned from route's
-- branches before any moved into the table (the tagged cascade); the conversion keeps every chain. Re-pin with
-- RULES_CAPTURE=<file>.
-- The rules no matrix case reaches, each pinned by an existing pairing spec's chain (Game.State.helpers.rule_trace):
-- tickets_spec (replace_provisional, swing_wound_first, wound_remembered, credit_core_band, overdue, tied_wound,
-- unmapped_excuse, give_back), pairing_replay_spec (wound_zero), now_spec (tie_crit_not_cast, latest_success_tie),
-- cleu_rows_spec (cast_wound_wide), tie_holder_wound (tickets_spec, added by lane 9: no test reached it before).
local UNREACHED = {
    "wound_zero",
    "replace_provisional",
    "swing_wound_first",
    "tie_crit_not_cast",
    "credit_core_band",
    "tie_holder_wound",
    "cast_wound_wide",
    "overdue",
    "tied_wound",
    "unmapped_excuse",
    "wound_remembered",
    "latest_success_tie",
    "give_back",
}
local RULE_PIN = {
    ["1 Rip MISS own row +4 ms"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["2 Rip MISS row -15 ms (fix A)"] = "-0.426 WOUND secret_wound_landed>secret_row; -0.015 MISS hold_early_avoid; -0.015 MISS held_row_at_success>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["3 Rip MISS swing frame, secret"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rip MISS swing frame, secret, viewer"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rip MISS swing frame, plain"] = "+0.003 WOUND swing_score>credit_swing>=swing1; +0.004 MISS cast_narrow>pay_cast>=cast; +1.003 WOUND swing_score>credit_swing>=swing1; +1.500 WOUND foreign; +2.003 WOUND swing_score>credit_swing>=swing1",
    ["3b Rip MISS swing -16 ms (SAME_FRAME)"] = "-0.542 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +0.458 WOUND secret_wound_landed>secret_row; +1.458 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +2.458 WOUND secret_wound_landed>secret_row",
    ["4 Rip MISS no row, viewer dark"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["1 Rip DODGE own row +4 ms"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["2 Rip DODGE row -15 ms (fix A)"] = "-0.426 WOUND secret_wound_landed>secret_row; -0.015 DODGE hold_early_avoid; -0.015 DODGE held_row_at_success>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["3 Rip DODGE swing frame, secret"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rip DODGE swing frame, secret, viewer"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rip DODGE swing frame, plain"] = "+0.003 WOUND swing_score>credit_swing>=swing1; +0.004 DODGE cast_narrow>pay_cast>=cast; +1.003 WOUND swing_score>credit_swing>=swing1; +1.500 WOUND foreign; +2.003 WOUND swing_score>credit_swing>=swing1",
    ["3b Rip DODGE swing -16 ms (SAME_FRAME)"] = "-0.542 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +0.458 WOUND secret_wound_landed>secret_row; +1.458 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +2.458 WOUND secret_wound_landed>secret_row",
    ["4 Rip DODGE no row, viewer dark"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["1 Rip PARRY own row +4 ms"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["2 Rip PARRY row -15 ms (fix A)"] = "-0.426 WOUND secret_wound_landed>secret_row; -0.015 PARRY hold_early_avoid; -0.015 PARRY held_row_at_success>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["3 Rip PARRY swing frame, secret"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rip PARRY swing frame, secret, viewer"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rip PARRY swing frame, plain"] = "+0.003 WOUND swing_score>credit_swing>=swing1; +0.004 PARRY cast_narrow>pay_cast>=cast; +1.003 WOUND swing_score>credit_swing>=swing1; +1.500 WOUND foreign; +2.003 WOUND swing_score>credit_swing>=swing1",
    ["3b Rip PARRY swing -16 ms (SAME_FRAME)"] = "-0.542 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +0.458 WOUND secret_wound_landed>secret_row; +1.458 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +2.458 WOUND secret_wound_landed>secret_row",
    ["4 Rip PARRY no row, viewer dark"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["5 Rip DODGE no row, cdmOff"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["5 Rip DODGE no row, not tracked"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["1 Rake MISS own row +4 ms"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["2 Rake MISS row -15 ms (fix A)"] = "-0.426 WOUND secret_wound_landed>secret_row; -0.015 MISS hold_early_avoid; -0.015 MISS held_row_at_success>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["3 Rake MISS swing frame, secret"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rake MISS swing frame, secret, viewer"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rake MISS swing frame, plain"] = "+0.003 WOUND cast_narrow>pay_cast>=cast; +0.004 MISS swing_score>credit_swing>=swing1; +1.003 WOUND swing_score>credit_swing>=swing1; +2.003 WOUND swing_score>credit_swing>=swing1",
    ["3b Rake MISS swing -16 ms (SAME_FRAME)"] = "-0.542 WOUND secret_wound_landed>secret_row; +0.004 MISS cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +0.458 WOUND secret_wound_landed>secret_row; +1.458 WOUND secret_wound_landed>secret_row; +2.458 WOUND secret_wound_landed>secret_row",
    ["4 Rake MISS no row, viewer dark"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["1 Rake DODGE own row +4 ms"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["2 Rake DODGE row -15 ms (fix A)"] = "-0.426 WOUND secret_wound_landed>secret_row; -0.015 DODGE hold_early_avoid; -0.015 DODGE held_row_at_success>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["3 Rake DODGE swing frame, secret"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rake DODGE swing frame, secret, viewer"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rake DODGE swing frame, plain"] = "+0.003 WOUND cast_narrow>pay_cast>=cast; +0.004 DODGE swing_score>credit_swing>=swing1; +1.003 WOUND swing_score>credit_swing>=swing1; +2.003 WOUND swing_score>credit_swing>=swing1",
    ["3b Rake DODGE swing -16 ms (SAME_FRAME)"] = "-0.542 WOUND secret_wound_landed>secret_row; +0.004 DODGE cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +0.458 WOUND secret_wound_landed>secret_row; +1.458 WOUND secret_wound_landed>secret_row; +2.458 WOUND secret_wound_landed>secret_row",
    ["4 Rake DODGE no row, viewer dark"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["1 Rake PARRY own row +4 ms"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["2 Rake PARRY row -15 ms (fix A)"] = "-0.426 WOUND secret_wound_landed>secret_row; -0.015 PARRY hold_early_avoid; -0.015 PARRY held_row_at_success>pay_cast>=cast; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["3 Rake PARRY swing frame, secret"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rake PARRY swing frame, secret, viewer"] = "+0.003 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["3 Rake PARRY swing frame, plain"] = "+0.003 WOUND cast_narrow>pay_cast>=cast; +0.004 PARRY swing_score>credit_swing>=swing1; +1.003 WOUND swing_score>credit_swing>=swing1; +2.003 WOUND swing_score>credit_swing>=swing1",
    ["3b Rake PARRY swing -16 ms (SAME_FRAME)"] = "-0.542 WOUND secret_wound_landed>secret_row; +0.004 PARRY cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +0.458 WOUND secret_wound_landed>secret_row; +1.458 WOUND secret_wound_landed>secret_row; +2.458 WOUND secret_wound_landed>secret_row",
    ["4 Rake PARRY no row, viewer dark"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["5 Rake DODGE no row, cdmOff"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["5 Rake DODGE no row, not tracked"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["C Rip lands"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.000 WOUND secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["C Rake lands"] = "-0.426 WOUND secret_wound_landed>secret_row; +0.004 WOUND secret_row; +0.574 WOUND secret_wound_landed>secret_row; +1.574 WOUND secret_wound_landed>secret_row; +2.574 WOUND secret_wound_landed>secret_row",
    ["M seed 2, secret"] = "-0.191 WOUND secret_wound_landed>secret_row; +0.511 DODGE cast_avoid_wide>secret_avoid_past_frame>foreign; +1.500 WOUND secret_row; +1.809 WOUND secret_wound_landed>secret_row; +2.000 WOUND secret_row; +2.809 WOUND secret_wound_landed>secret_row",
    ["M seed 2, plain"] = "-0.191 WOUND swing_score>credit_swing>=swing1; +0.511 DODGE cast_avoid_wide>swing_owes_row>credit_swing>=swing1; +1.500 WOUND swing_score>credit_swing>=swing1; +1.809 WOUND reroute>swing_replaces_credit>credit_swing>=swing1; +2.000 WOUND foreign; +2.809 WOUND swing_score>credit_swing>=swing1",
    ["M seed 8, secret"] = "-0.521 WOUND secret_wound_landed>secret_row; +0.625 MISS cast_avoid_wide>secret_avoid_past_frame>swing_score>credit_swing>=swing1; +1.479 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +2.000 WOUND secret_row; +2.479 WOUND secret_wound_landed>secret_row",
    ["M seed 8, plain"] = "-0.521 WOUND swing_score>credit_swing>=swing1; +0.625 MISS cast_avoid_wide>swing_owes_row>credit_swing>=swing1; +1.479 WOUND swing_score>credit_swing>=swing1; +1.500 WOUND foreign; +2.000 WOUND foreign; +2.479 WOUND swing_score>credit_swing>=swing1",
    ["M core band, secret"] = "+0.003 MISS cast_narrow>swing_wins_tie>swing_score>credit_swing>=swing1; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.000 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["M core band, plain"] = "+0.003 MISS cast_narrow>swing_wins_tie>swing_score>credit_swing>=swing1; +1.003 WOUND swing_score>credit_swing>=swing1; +1.500 WOUND foreign; +2.000 WOUND swing_score>credit_swing>=swing1; +2.003 WOUND foreign",
    ["M own ms, plain"] = "-0.515 WOUND swing_score>credit_swing>=swing1; +0.011 MISS cast_narrow>swing_wins_tie>swing_score>credit_swing>=swing1; +1.485 WOUND swing_score>credit_swing>=swing1; +1.500 WOUND foreign; +2.000 WOUND foreign; +2.485 WOUND swing_score>credit_swing>=swing1",
    ["M own ms, secret (PINNED)"] = "-0.515 WOUND secret_wound_landed>secret_row; +0.011 MISS cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +1.485 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +2.000 WOUND secret_row; +2.485 WOUND secret_wound_landed>secret_row",
    ["M own ms, secret, viewer"] = "-0.515 WOUND secret_wound_landed>secret_row; +0.011 MISS cast_narrow>swing_wins_tie>tie_refused>pay_cast>=cast; +1.485 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_wound_landed>secret_row; +2.000 WOUND secret_row; +2.485 WOUND secret_wound_landed>secret_row",
    ["M tick, secret (PINNED)"] = "+0.002 WOUND secret_wound_landed>secret_row; +0.003 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.000 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["M tick, secret, viewer"] = "+0.002 WOUND secret_wound_landed>secret_row; +0.003 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.003 WOUND secret_wound_landed>secret_row; +1.500 WOUND secret_row; +2.000 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["M seed 2, plain, viewer"] = "-0.191 WOUND swing_score>credit_swing>=swing1; +0.511 DODGE cast_avoid_wide>swing_owes_row>credit_swing>=swing1; +1.500 WOUND swing_score>credit_swing>=swing1; +1.809 WOUND reroute>swing_replaces_credit>credit_swing>=swing1; +2.000 WOUND foreign; +2.809 WOUND swing_score>credit_swing>=swing1",
    ["P Rake lands, swing MISS core band"] = "+0.001 WOUND secret_wound_landed>secret_row; +0.030 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.030 WOUND secret_wound_landed>secret_row; +2.030 WOUND secret_wound_landed>secret_row",
    ["P Rake lands, 2 points"] = "+0.001 WOUND secret_wound_landed>secret_row; +0.030 MISS cast_narrow>swing_secret_first>pay_cast>=cast; +1.030 WOUND secret_wound_landed>secret_row; +2.030 WOUND secret_wound_landed>secret_row",
    ["P Rake MISS tied to open swing"] = "+0.004 MISS cast_narrow>swing_wins_tie>swing_score>credit_swing>=swing1; +0.729 MISS foreign; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["P Rake DODGE tied to open swing"] = "+0.004 DODGE cast_narrow>swing_wins_tie>swing_score>credit_swing>=swing1; +0.729 MISS foreign; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
    ["P Rake PARRY tied to open swing"] = "+0.004 PARRY cast_narrow>swing_wins_tie>swing_score>credit_swing>=swing1; +0.729 MISS foreign; +1.003 WOUND secret_wound_landed>secret_row; +2.003 WOUND secret_wound_landed>secret_row",
}

local function chains(knobs)
    local c, out, cur, base = {}, {}, nil, nil
    for k, v in pairs(knobs) do
        c[k] = v
    end
    c.rows = true
    if c.bleed == "rake" and c.act ~= "WOUND" and not c.pointFact then
        c.pointFact = PT_AVOID
        c.info = c.info or math.max(PT_AVOID, c.row or 0)
    end
    local events = {}
    c.onWorld = function(W)
        local I = W.I
        local RULES, Tk = I.Rows.RULES, I.Tickets
        I.Rows.trace = function(what, a, b)
            if what == "row" then
                events[#events + 1] = { a, b, {} }
            elseif #events > 0 then
                local e = events[#events][3]
                if what == "rule" then
                    e[#e + 1] = RULES[a][1]
                elseif what == "cast" then
                    e[#e + 1] = "=cast"
                else
                    e[#e + 1] = "=swing" .. Tk.x[a]
                end
            end
        end
    end
    local W, T = fw.case(c)
    for _, e in ipairs(events) do
        local d = e[1] - T
        if d > -0.6 and d < 3 then
            out[#out + 1] = ("%+.3f %s %s"):format(d, e[2], table.concat(e[3], ">"))
        end
    end
    assert.are.same({}, W.H.errors)
    return table.concat(out, "; ")
end

describe("the claim table's deciding rules on each matrix case (refactor lane 9)", function()
    local capture = os.getenv("RULES_CAPTURE")
    for _, m in ipairs(MATRIX) do
        it("rules: " .. m[1], function()
            local got = chains(m[2])
            if capture then
                local out = assert(io.open(capture, "a"))
                out:write(("    [%q] = %q,\n"):format(m[1], got))
                out:close()
            end
            assert.are.equal(RULE_PIN[m[1]], got)
        end)
    end

    -- the table's order is precedence: pinned whole (the chains pin it only where rules meet in one row)
    it("rules: the table's names in their order", function()
        local W, names = fw.world({}), {}
        for _, r in ipairs(W.I.Rows.RULES) do
            names[#names + 1] = r[1]
        end
        assert.are.same({
            "secret_wound_landed",
            "secret_row",
            "wound_zero",
            "cast_narrow",
            "replace_provisional",
            "held_row_at_success",
            "hold_early_avoid",
            "cast_avoid_wide",
            "secret_avoid_past_frame",
            "swing_wound_first",
            "swing_secret_first",
            "swing_wins_tie",
            "tie_crit_not_cast",
            "credit_core_band",
            "swing_owes_row",
            "swing_score",
            "swing_replaces_credit",
            "tie_holder_wound",
            "cast_wound_wide",
            "tie_refused",
            "overdue",
            "tied_wound",
            "unmapped_excuse",
            "pay_cast",
            "wound_remembered",
            "foreign",
            "credit_swing",
            "latest_success_tie",
            "give_back",
            "reroute",
        }, names)
    end)

    -- the rules no pinned chain reaches (pinned by their own specs: tickets_spec, now_spec, row_feed_spec and others)
    it("rules: the table's rules no matrix case reaches", function()
        local W = fw.world({})
        local seen, missing = {}, {}
        for _, chain in pairs(RULE_PIN) do
            for name in chain:gmatch("[%a_]+") do
                seen[name] = true
            end
        end
        for _, r in ipairs(W.I.Rows.RULES) do
            if not seen[r[1]] then
                missing[#missing + 1] = r[1]
            end
        end
        assert.are.same(UNREACHED, missing)
    end)
end)
