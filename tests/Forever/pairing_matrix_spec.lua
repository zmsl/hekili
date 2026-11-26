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
