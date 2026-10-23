-- tests/Game/harness/captures_spec.lua (unit-registry spec §6.3, K20): every saved 2026-10-22 capture replayed through
-- the real sources (registry, tickets, rows) with its exact credits, so the suite is anchored on the game.
local drive = require("Game.harness.drive")
local fs = require("Game.State.helpers.fake_spec")

local BASE = 1

-- A booted VirtualState with the expect abilities, a 30 yd projectile, and (`stub`) the death events refused.
local function boot(stub)
    return drive.boot({
        boot = function(c)
            for _, e in ipairs(stub and { "UNIT_DIED", "PLAYER_TARGET_DIED", "PARTY_KILL" } or {}) do
                c.ctl.unknownEvents[e] = true
            end
            c.I.Build(fs.def(fs.new(9, false, false, true)), 0.1)
            c.VS.Start(c.api)
            c.I.ab.rMax[c.I.ab.bySpell[fs.SPENDER_P]] = 30
        end,
    })
end

local function replay(name, stub, extra, from)
    local fix = dofile("tests/Game/harness/fixtures/" .. name .. ".lua")
    if from then
        local rows = {}
        for _, r in ipairs(fix.rows) do
            if r[1] >= from or r[2] == "T" then -- the target lines keep their binding
                rows[#rows + 1] = r
            end
        end
        fix = { damage = fix.damage, rows = rows }
    end
    local c = boot(stub)
    local s = drive.fixtureStream(fix, BASE, false, extra)
    drive.run(c, s)
    drive.restore(c)
    return c, s
end

-- The stream index of the first non-player UNIT_COMBAT at `ms` with action `act` (and school `sch`).
local function at(s, ms, act, sch)
    for i = 1, s.n do
        if
            s.ev[i] == "UNIT_COMBAT"
            and math.abs(s.t[i] - (BASE + ms / 1000)) < 1e-6
            and s.a1[i] ~= "player"
            and s.a1[i] ~= "targettarget"
            and s.a2[i] == act
            and (sch == nil or s.a5[i] == sch)
        then
            return i
        end
    end
    error("no row at " .. ms)
end

-- The ticket that paid the outcome at `ms` (any of its tokens): its anchor, kind, what it staged and the pass, else 0s.
local function paid(c, s, ms, act, sch)
    local i = at(s, ms, act, sch)
    for j = i, s.n do
        if s.t[j] ~= s.t[i] then
            break
        elseif c.payAt[j] > 0 then
            return c.payAt[j], c.payKind[j], c.staged[j], c.payPass[j]
        end
    end
    return 0, 0, 0, 0
end

describe("the 2026-10-22 captures (K20)", function()
    it("b: every projectile landing pays its ticket; the late miss pays and is avoided; each kill tells", function()
        local c, s = replay("capture_b", true)
        local X = c.I.Expect
        local n = 0
        for i = 1, s.n do
            if s.ev[i] == "UNIT_COMBAT" and s.a2[i] == "WOUND" and s.a5[i] == 8 and c.payKind[i] == X.FLIGHT then
                n = n + 1
            end
        end
        assert.are.equal(14, n) -- 0 of 14 before (unit-registry spec §1 row 1)
        local _, kind, staged = paid(c, s, 71327, "MISS")
        assert.are.same({ X.FLIGHT, 2 }, { kind, staged })
        assert.are.equal(0, c.L.bg[7])
        assert.are.equal(3, c.I.Units.deaths.tell)
        local _, k2 = paid(c, s, 74805, "WOUND")
        assert.are.equal(X.FLIGHT, k2) -- on the plate and softinteract only, after the clear
    end)

    it("c-swap: the plate-only landing pays the cast pinned at SENT to the old mob; the post-clear row pays", function()
        local c, s = replay("capture_swap")
        local X = c.I.Expect
        local a, k = paid(c, s, 216184, "WOUND")
        assert.are.same({ BASE + 215818 / 1000, X.FLIGHT }, { a, k })
        local _, k2 = paid(c, s, 219922, "WOUND")
        assert.are.equal(X.FLIGHT, k2)
    end)

    -- capture a has no landing for the 95824 cast and pools its four mobs under one inferred GUID, so the 97891 MISS
    -- meets a record last refreshed at 34986 (spec §3.4's example assumed a fresh one) whose pooled spread (0.355 s) makes
    -- even the narrow band wide: it pays the 97374 ticket at pass 1, and that cast's real landing (98890, 1.516 s)
    -- finds no ticket.
    -- probe U13: what was the 95824 cast's outcome? A 2.07 s landing on a fleeing mob exceeds the hard window; the
    -- projectile's range with its range talent is 36 yd: check whether the pack's rMax includes it.
    it(
        "a: the crit stages Crit; the late MISS pays on the stale pooled record; the real landing stages nothing",
        function()
            local c, s = replay("capture_a")
            local X = c.I.Expect
            local _, _, staged = paid(c, s, 5367, "WOUND")
            assert.are.equal(1, staged)
            assert.are.same({ BASE + 97374 / 1000, X.FLIGHT, 2, 1 }, { paid(c, s, 97891, "MISS") })
            local i = at(s, 98890, "WOUND")
            for j = i, s.n do
                if s.t[j] ~= s.t[i] then
                    break
                end
                assert.are.same({ 0, 0 }, { c.payAt[j], c.staged[j] })
            end
        end
    )

    it("a: the same MISS pays the 97374 ticket under the first-ticket rule (no learned lag)", function()
        local c, s = replay("capture_a", false, nil, 97000)
        assert.are.equal(BASE + 97374 / 1000, (paid(c, s, 97891, "MISS")))
    end)

    it("rogue b: strikes pay their frames, the life-steal row is foreign, white hits pay their swings", function()
        local c, s = replay("capture_strike")
        local X = c.I.Expect
        local function pk(ms, sch)
            local a, k = paid(c, s, ms, "WOUND", sch)
            return { a, k }
        end
        assert.are.same({ BASE + 630 / 1000, X.FRAME }, pk(630))
        assert.are.same({ BASE + 2248 / 1000, X.FRAME }, pk(2250, 1))
        assert.are.same({ 0, 0 }, pk(2250, 32))
        assert.are.same({ BASE + 628 / 1000, X.MELEE }, pk(1617)) -- the first swing: 989 ms, teaches nothing
        assert.are.same({ BASE + 2250 / 1000, X.MELEE }, pk(2702))
        assert.are.same({ BASE + 3500 / 1000, X.FRAME }, pk(3501)) -- before the clear at 3602
    end)

    -- the post-clear white killing row (452 ms after the clear, on softinteract only) pays its swing
    it("rogue kill-events: the death events mark the unit ours; the corpse's row pays the killing swing", function()
        local c, s = replay("capture_kill")
        local X, U = c.I.Expect, c.I.Units
        local a, k = paid(c, s, 4820, "WOUND")
        assert.are.same({ BASE + 4364 / 1000, X.MELEE }, { a, k })
        assert.are.equal(0, (paid(c, s, 2765, "WOUND", 32)))
        local u = U.Find("Creature-0-6782-0-9-1508-AE12DF4C33")
        assert.is_true(U.IsDead(u) and U.Ours(u))
    end)

    it("druid moonfire: direct hits pay FRAME, ticks pay on schedule, a recast refreshes, the kill closes", function()
        local died = { { 21926, "D", "Creature-0-4621-1-7-2955-C057713E6D" } }
        local c, s = replay("capture_ticks", false, died)
        local X, T = c.I.Expect, c.I.Tickets
        for _, ms in ipairs({ 2000, 11788, 21924 }) do
            assert.are.equal(X.FRAME, select(2, paid(c, s, ms, "WOUND")))
        end
        for _, ms in ipairs({ 5036, 8020, 11000 + 70, 14755, 17722, 20755 }) do
            assert.are.equal(X.TICKS, select(2, paid(c, s, ms, "WOUND")), "tick at " .. ms)
        end
        assert.is_true(T.closed.refreshed >= 1 and T.closed.dead >= 1)
    end)
end)
