-- tests/Game/harness/detect_more_b_spec.lua (unit-registry spec §6.2 K10-K19, #slow): the detection suite's last kinds
-- and K16/K17, split out of detect_more_spec.lua (test-speed plan, Task 4) so the two files' summed seconds are near
-- equal; each cell: detect_more_cells.lua.
local detect = require("Game.harness.detect")
local metrics = require("Game.harness.metrics")
local alloc = require("Game.State.helpers.alloc")
local drive = require("Game.harness.drive")
local scenarios = require("Game.harness.scenarios")
local cells = require("Game.harness.detect_more_cells")

describe("detection suite K10-K19 #slow", function()
    for _, kind in ipairs({
        "K19",
        "K21",
    }) do
        for _, band in ipairs(detect.GATED) do
            it(kind .. " in " .. band, function()
                cells.run(kind, band)
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
