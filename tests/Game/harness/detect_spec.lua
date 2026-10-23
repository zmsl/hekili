-- tests/Game/harness/detect_spec.lua (unit-registry spec §6.2, #slow): detection kinds K1-K9 x density bands, scored
-- against tickets. Gated bands (solo, party-light, busy 5-man) assert their floors (detect_floors.lua, written by the
-- first clean run with DETECT_WRITE=1); raid bands (12, 25, 40) print their numbers and assert only that they ran.
local detect = require("Game.harness.detect")
local metrics = require("Game.harness.metrics")

describe("detection suite K1-K9 #slow", function()
    for _, kind in ipairs({ "K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "K9" }) do
        for _, band in ipairs(detect.GATED) do
            it(kind .. " in " .. band, function()
                local m = detect.run(kind, band, 20, 1)
                print(("\n%s %s: %s"):format(kind, band, metrics.ticketLine(m)))
                detect.record(kind, band, m)
                detect.check(kind, band, m) -- K6's post-clear rows too: a floor (Task 12 ruling), not every row
            end)
        end
        for _, band in ipairs(detect.MEASURED) do
            it(kind .. " in " .. band .. " (measured)", function()
                local m = detect.run(kind, band, 5, 1)
                print(("\n%s %s (measured): %s"):format(kind, band, metrics.ticketLine(m)))
                assert.are.equal(5, m.fights)
            end)
        end
    end

    it("K9: equal twins from two sources on plate and target dispatch twice; one hit on three tokens once", function()
        local m = detect.twins()
        assert.are.same({ 2, 1 }, { m.twins, m.single })
    end)
end)
