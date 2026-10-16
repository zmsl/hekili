-- tests/Virtual/harness/sweep_spec.lua (harness design §3.4, D4): solo, levels 10-60 x armour DR 0 / 0.15 / 0.30, 20
-- fights a cell. DR 0 holds the solo gates; DR 0.30 (main-hand hits pushed into the off hand's range) keeps the wrong
-- hand at <= 5%; DR 0.15 is reported. Slow: run by `make check` (split it out if it passes 20 s).
local metrics = require("Virtual.harness.metrics")

describe("the level and armour sweep #slow", function()
    for _, level in ipairs({ 10, 20, 30, 40, 50, 60 }) do
        for _, dr in ipairs({ 0, 0.15, 0.30 }) do
            it(("level %d, DR %.2f"):format(level, dr), function()
                local m = metrics.fights({ level = level, dr = dr }, 20)
                if dr == 0 then
                    assert.is_true(metrics.rate(m, 1) >= 0.94 and metrics.rate(m, 2) >= 0.94, metrics.line(m))
                    assert.is_true(m.wrong[1] + m.wrong[2] <= 0.02 * (m.own[1] + m.own[2]), metrics.line(m))
                    assert.is_true(m.over == 0, metrics.line(m))
                elseif dr == 0.30 then
                    assert.is_true(m.wrong[1] + m.wrong[2] <= 0.05 * (m.own[1] + m.own[2]), metrics.line(m))
                else
                    print(("\nlevel %d DR 0.15: %s"):format(level, metrics.line(m)))
                end
            end)
        end
    end
end)
