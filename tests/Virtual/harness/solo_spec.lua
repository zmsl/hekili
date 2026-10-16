-- tests/Virtual/harness/solo_spec.lua (harness design §3.4, decisions D4-D5): solo fights of the log-2 profile, a
-- damage buff in combat and a form change, through the real Rows.lua; the gates of §3.4.
local metrics = require("Virtual.harness.metrics")

local function check(ok, m)
    assert.is_true(ok, metrics.line(m))
end

describe("solo attribution (harness gates) #slow", function()
    it(
        "credits >= 94% of each hand's hits to the right swing, <= 2% to the wrong one, no overshoot (200 fights)",
        function()
            local m = metrics.fights({}, 200)
            check(metrics.rate(m, 1) >= 0.94 and metrics.rate(m, 2) >= 0.94, m)
            check(m.wrong[1] <= 0.02 * m.own[1] and m.wrong[2] <= 0.02 * m.own[2], m)
            check(m.over == 0 and m.falses[1] + m.falses[2] == 0, m)
            check(m.noDst == 0 and m.order == 0 and m.nonTarget == 0, m)
        end
    )

    it(
        "credits >= 85% of the main hand's hits after a +20% damage buff in combat, falsely none (100 fights)",
        function()
            local m = metrics.fights({ damageBuff = 30 }, 100, 31)
            check(metrics.rate(m, 1) >= 0.85 and m.falses[1] + m.falses[2] == 0, m)
        end
    )

    it(
        "credits >= 85% of the hits after a form change (amount unknown: timing alone), falsely none (100 fights)",
        function()
            local m = metrics.fights({ formAt = 30 }, 100, 31)
            check(metrics.rate(m, 1) >= 0.85 and metrics.rate(m, 2) >= 0.85, m)
            check(m.falses[1] + m.falses[2] == 0, m)
        end
    )
end)
