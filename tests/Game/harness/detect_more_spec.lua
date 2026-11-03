-- tests/Game/harness/detect_more_spec.lua (unit-registry spec §6.2 K10-K19, #slow): the owner's added kinds, gated in
-- solo, party-light and busy, with their own floors (detect_floors.lua) and K-specific checks.
-- The kinds' second part and K16/K17: detect_more_b_spec.lua (test-speed plan, Task 4); each cell: detect_more_cells.lua.
local detect = require("Game.harness.detect")
local cells = require("Game.harness.detect_more_cells")

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
    }) do
        for _, band in ipairs(detect.GATED) do
            it(kind .. " in " .. band, function()
                cells.run(kind, band)
            end)
        end
    end
end)
