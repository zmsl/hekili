-- tests/Game/harness/detect_more_cells.lua: one K10-K19 cell of the detection suite (unit-registry spec §6.2), run,
-- recorded and checked against its floor (detect_floors.lua) with its K-specific checks; moved out of
-- detect_more_spec.lua (test-speed plan, Task 4) so detect_more_spec.lua and detect_more_b_spec.lua share it.
local assert = require("luassert")
local detect = require("Game.harness.detect")
local metrics = require("Game.harness.metrics")

local M = {}

--- The cell of `kind` in `band`: 20 fights at seed 101.
function M.run(kind, band)
    local na = (detect.KINDS[kind].na or {})[band]
    if na then -- not applicable: measured as nothing, no floor
        print(("\n%s %s: na (%s)"):format(kind, band, na))
        return
    end
    local m = detect.run(kind, band, 20, 101)
    print(("\n%s %s: %s"):format(kind, band, metrics.ticketLine(m)))
    detect.record(kind, band, m)
    detect.check(kind, band, m)
    if kind == "K11" then
        assert.is_true(m.inFlight >= 10, "in-flight foreign kills " .. m.inFlight .. " of 20")
        -- a bolt whose unit died in its flight closes dead (or ended, when combat ends first), never lost
        -- or paid; the crowd's other losses (K4's mechanism) are lostDiff's floor in detect.check
        assert.is_true(m.dead > 0 and m.inFlightLost == 0, metrics.ticketLine(m))
        assert.are.equal(m.postClear, m.postClearPaid) -- our pending swing's row after the clear pays
        assert.are.equal(m.kills, m.gone) -- TargetGone once per kill of our target
    elseif kind == "K11m" then -- our swing pending at a kill: its row after the clear (a floor, as K6)
        assert.is_true(m.own > 0 and m.postClear > 0, metrics.ticketLine(m))
        print(("K11m %s post-clear rows paid by their swing: %d of %d"):format(band, m.postClearPaid, m.postClear))
    elseif kind == "K14p" then
        -- spec §6.2 K14: our pet's rows stay foreign. Our swing tickets take some pet white rows inside
        -- their landing window (the melee likelihood, probe U15's family): an owner finding, floored by
        -- its first clean run (detect.NOTES.K14p), printed here.
        assert.is_true(m.petRows > 0, "no pet rows")
        print(
            ("K14p %s pet rows paid by our tickets: %d of %d (%.2f per 100): %s"):format(
                band,
                m.petPaid,
                m.petRows,
                100 * m.petPaid / m.petRows,
                m.petPaid == 0 and "met" or "UNMET"
            )
        )
    elseif kind:match("^K13") then
        -- spec §4.2's claim: each divergent pair costs at most one own outcome, and false credit stays
        -- within K4's plus the divergent rate. Asserted in solo only; in party and busy the crowd's cost
        -- dominates (the twin is one more same-school source, K8's mechanism), so those cells are floors.
        -- Divergent pairs are the harness's (metrics.tickets: a swapped pair of a different class); the
        -- engine's T.divergent counts only an avoid two of our own tickets could own.
        local k4 = detect.floors().K4[band]
        local div = metrics.twinDivergent100(m)
        local perPair = m.twinDivergent > 0 and m.missed / m.twinDivergent or m.missed
        print(
            (
                "%s %s divergent pairs per 100 own: %.2f (harness; engine T.divergent %.2f sees own pairs only);"
                .. " own missed per divergent pair %.2f; false %.2f against K4's %.2f + divergent"
            ):format(kind, band, div, metrics.divergent100(m), perPair, metrics.false100(m), k4.false100)
        )
        if band == "solo" then
            assert.is_true(perPair <= 1.0, metrics.ticketLine(m))
            assert.is_true(metrics.false100(m) <= k4.false100 + div + 1e-9, metrics.ticketLine(m))
        end
    elseif kind == "K17" then
        assert.is_true(m.ended > 0 and m.afterReset == 0, metrics.ticketLine(m))
    elseif kind == "K18" then
        assert.is_true(m.aoeOther > 0 and m.wrong == 0, metrics.ticketLine(m))
    elseif kind == "K14f" then -- the credit rate for the ledger (UR5), beside the floors
        local mm = m.melee
        print(
            ("K14f %s credit rate main %.2f off %.2f, rage error mean %.2f"):format(
                band,
                metrics.rate(mm, 1),
                metrics.rate(mm, 2),
                mm.windows > 0 and mm.errSum / mm.windows or 0
            )
        )
    elseif kind == "K21" then -- a projectile and a schedule of one school on one GUID: each pays its own
        assert.is_true(m.own > 0 and m.wrong == 0, metrics.ticketLine(m))
    end
end

return M
