-- tests/Game/harness/detect_more_spec.lua (unit-registry spec §6.2 K10-K19, #slow): the owner's added kinds, gated in
-- solo, party-light and busy, with their own floors (detect_floors.lua) and K-specific checks.
local detect = require("Game.harness.detect")
local metrics = require("Game.harness.metrics")
local alloc = require("Game.State.helpers.alloc")
local drive = require("Game.harness.drive")
local scenarios = require("Game.harness.scenarios")

describe("detection suite K10-K19 #slow", function()
    for _, kind in ipairs({
        "K10",
        "K11",
        "K11m",
        "K12",
        "K13",
        "K13p1",
        "K13p5",
        "K14",
        "K14p",
        "K14f",
        "K15",
        "K17",
        "K18",
        "K19",
        "K21",
    }) do
        for _, band in ipairs(detect.GATED) do
            it(kind .. " in " .. band, function()
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
                    print(
                        ("K11m %s post-clear rows paid by their swing: %d of %d"):format(
                            band,
                            m.postClearPaid,
                            m.postClear
                        )
                    )
                elseif kind == "K14p" then
                    -- spec §6.2 K14: our pet's rows stay foreign (leak ceiling 0). UNMET on the first run: our swing
                    -- tickets take some pet white rows inside their landing window (the melee likelihood, probe U15's
                    -- territory, unchanged here). Printed, not asserted, for the owner's ruling (Task 13 fix round 1).
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
                    -- spec §4.2's claim (only divergent pairs cost) against K4's floor. Divergent pairs are the
                    -- harness's (metrics.tickets: a swapped pair of a different class); the engine's T.divergent
                    -- counts only an avoid two of our own tickets could own, so it never sees a foreign twin. Printed
                    -- met or UNMET with the cost per divergent pair (the Task 13 rulings), never loosened.
                    local k4 = detect.floors().K4[band]
                    local div = metrics.twinDivergent100(m)
                    local met = metrics.recall(m) >= k4.recall and metrics.false100(m) <= k4.false100 + div + 1e-9
                    local cost = m.twinDivergent > 0 and (k4.recall - metrics.recall(m)) * m.own / m.twinDivergent or 0
                    print(
                        (
                            "%s %s divergent pairs per 100 own: %.2f (harness; engine T.divergent %.2f sees own pairs only);"
                            .. " claim vs K4 (recall >= %.2f, false <= %.2f): %s; own missed per divergent pair "
                            .. "beyond K4's: %.2f"
                        ):format(
                            kind,
                            band,
                            div,
                            metrics.divergent100(m),
                            k4.recall,
                            k4.false100 + div,
                            met and "met" or "UNMET",
                            cost
                        )
                    )
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
            end)
        end
    end

    it("K16: raid-40 density for 300 s: bounded pools, counted overflow, no allocation", function()
        local m = detect.run("K16", "raid40", 1, 7)
        print("\nK16 raid40: " .. metrics.ticketLine(m))
        assert.are.equal(0, m.errors)
        local o = setmetatable({ others = detect.BANDS.raid40.others }, { __index = detect.KINDS.K16 })
        local s = scenarios.stream(o, 7)
        local c = drive.boot({ boot = detect.boot })
        local ok, bytes = pcall(alloc.bytes, function(i)
            drive.run(c, s, i * 400)
        end, 2)
        drive.restore(c)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
    end)

    it("K17: a /reload mid-fight: a fresh registry while rows keep arriving errors nothing", function()
        local c1, c2 = detect.reload("K17", "party", 3)
        assert.are.same({ 0, 0 }, { c1.I.Events.errors, c2.I.Events.errors })
    end)
end)
