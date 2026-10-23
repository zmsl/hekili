-- tests/Game/harness/solo_spec.lua (harness design §3.4, decisions D4-D5): solo fights of the log-2 profile, a
-- damage buff in combat and a form change, through the real Rows.lua; the gates of §3.4. Every gate answers usability
-- from the true power, as the client always does (scenarios.oracle); the overshoot gate is the model's drift alone
-- (each window as if pinned at its start), so it reads a run without answers: the oracle's pins would count as error.
local metrics = require("Game.harness.metrics")
local scenarios = require("Game.harness.scenarios")

local ab = require("Game.harness.ab")

local function check(ok, m) -- a bar: asserted in the default arm, recorded in a provider arm (providers spec §4.1)
    ab.check(ok, "solo", metrics.line(m))
end

describe("solo attribution (harness gates) #slow", function()
    it(
        "credits >= 94% of each hand's hits to the right swing, <= 2% to the wrong one, overshoot <= 2; the oracle retracts "
            .. "<= 0.5% of our own credits (200 fights)",
        function()
            local m = metrics.fights(scenarios.oracle({}), 200)
            check(metrics.rate(m, 1) >= 0.94 and metrics.rate(m, 2) >= 0.94, m)
            check(m.wrong[1] <= 0.02 * m.own[1] and m.wrong[2] <= 0.02 * m.own[2], m)
            check(metrics.falsePer100(m, m.falseNet) == 0 and metrics.falsePer100(m) == 0, m)
            -- the model's drift, no answers. Re-based 0 -> 2 (measured 1 + 1; owner rulings 2026-10-23), decision 51,
            -- assumed outcomes at expiry: a refunded assumption is a believed step the truth never had; EV sizes it
            -- below a step, and no expectation once a white avoid nobody took fell in the window (avoidSeen);
            -- lo/danger stay 0
            check(metrics.fights({}, 200).over <= 2, m)
            -- row-only: an avoid of another source or an unexplained one credited pays no rage; bound at measured + 0.5
            check(metrics.falsePer100(m, m.falseAvoids) <= 0.6, m) -- measured 0.08
            check(m.noDst == 0 and m.order == 0 and m.nonTarget == 0, m)
            ab.check(m.falseRetracted <= 0.005 * (m.right[1] + m.right[2]), "solo", metrics.oracleLine(m))
            ab.check(m.judged > 0 and m.danger == 0, "solo", metrics.oracleLine(m))
        end
    )

    it(
        "credits >= 85% of the main hand's hits after a +20% damage buff in combat, no false wound credit (100 fights)",
        function()
            local m = metrics.fights(scenarios.oracle({ damageBuff = 30 }), 100, 31)
            check(metrics.rate(m, 1) >= 0.85 and metrics.falsePer100(m, m.falseNet) == 0, m)
            check(metrics.falsePer100(m) == 0, m) -- gross: measured 0 (measured + 1 would loosen it)
            -- row-only: an avoid of another source or an unexplained one credited pays no rage; bound at measured + 0.5
            check(metrics.falsePer100(m, m.falseAvoids) <= 0.66, m) -- measured 0.18
        end
    )

    it(
        "credits >= 85% of the hits after a form change (amount unknown: timing alone), <= 3% wrong, no false wound credit (100 fights)",
        function()
            local m = metrics.fights(scenarios.oracle({ formAt = 30 }), 100, 31)
            check(metrics.rate(m, 1) >= 0.85 and metrics.rate(m, 2) >= 0.85, m)
            check(metrics.falsePer100(m, m.falseNet) == 0, m)
            check(metrics.falsePer100(m) == 0, m) -- gross: measured 0 (measured + 1 would loosen it)
            -- row-only: an avoid of another source or an unexplained one credited pays no rage; bound at measured + 0.5
            check(metrics.falsePer100(m, m.falseAvoids) <= 0.6, m) -- measured 0.09
            check(m.wrong[1] <= 0.03 * m.own[1] and m.wrong[2] <= 0.03 * m.own[2], m)
        end
    )
end)
