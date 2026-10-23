-- tests/Game/harness/group_spec.lua (harness design §3.4, decisions D4-D5): other sources on our target (G fact 1:
-- their outcomes arrive on our target's tokens with plain amounts), through the real Rows.lua; the gates of §3.4. The
-- raid is reported, not gated (D5). Every gate answers usability from the true power, as the client always does
-- (scenarios.oracle): the spec's rage bounds apply to the false wounds net of the oracle's retractions; the gross ones
-- (as credited) are model-only error, bound at measured + 1. The overshoot gate is the model's drift alone (each window
-- as if pinned at its start), so it reads a run without answers: the oracle's pins would count as error.
-- Rows are not rescued (round 7 ruling): rage is gained at the swing (checkpoint R1), so a swing whose usability
-- answers showed its rage is already right in the belief (owe's lift); if its own wound never pairs it loses only its
-- SWING_DAMAGE row, and a wound taken for it after the fact was, in a group, mostly another source's (a wrong row is
-- worse than a missing one).
local metrics = require("Game.harness.metrics")
local scenarios = require("Game.harness.scenarios")

local ab = require("Game.harness.ab")

local function check(ok, m) -- a bar: asserted in the default arm, recorded in a provider arm (providers spec §4.1)
    ab.check(ok, "group", metrics.line(m))
end

describe("group attribution (harness gates) #slow", function()
    it("party of 5, a melee in our main range and a caster on our target (100 fights)", function()
        local plain = { others = { "melee", "caster" } }
        local m = metrics.fights(scenarios.oracle(plain), 100)
        local drift = metrics.fights(plain, 100)
        print("\nparty, no usability (reported): " .. metrics.line(drift))
        check(metrics.rate(m, 1) >= 0.75 and metrics.rate(m, 2) >= 0.85, m)
        check(metrics.falsePer100(m, m.falseNet) <= 4 and drift.over <= 0.05 * drift.windows, m)
        -- model-only error; the oracle removes the difference
        check(metrics.falsePer100(m) <= 2.76, m) -- measured 1.76
        -- row-only: an avoid of another source or an unexplained one credited pays no rage; bound at measured + 0.5
        check(metrics.falsePer100(m, m.falseAvoids) <= 0.84, m) -- measured 0.36
    end)

    it("party of 5 with a pet and a ranged stand-in on our target as well (100 fights)", function()
        local plain = { others = { "melee", "caster", "pet", "ranged" } }
        local m = metrics.fights(scenarios.oracle(plain), 100)
        local drift = metrics.fights(plain, 100)
        print("\nparty with a pet, no usability (reported): " .. metrics.line(drift))
        check(metrics.rate(m, 1) >= 0.70 and metrics.rate(m, 2) >= 0.70, m)
        check(metrics.falsePer100(m, m.falseNet) <= 6 and drift.over <= 0.10 * drift.windows, m)
        -- model-only error; the oracle removes the difference
        check(metrics.falsePer100(m) <= 7.33, m) -- measured 6.35
        -- row-only: an avoid of another source or an unexplained one credited pays no rage; bound at measured + 0.5
        check(metrics.falsePer100(m, m.falseAvoids) <= 1.4, m) -- measured 0.81
    end)

    it("raid, 12 on our target: reported (30 fights)", function()
        local others = {}
        for i = 1, 12 do
            others[i] = ({ "melee", "melee", "caster", "pet", "ranged", "melee" })[i % 6 + 1]
        end
        local m = metrics.fights({ others = others }, 30)
        print("\nraid, 12 on target: " .. metrics.line(m))
        assert.is_true(m.fights == 30)
    end)

    -- The population (round 7 ruling): rage-false credits only, a credit of another source's outcome whose rage differs
    -- from the truth: our swing was avoided, none of ours was due, or the kinds differ (crit or not) where a crit pays
    -- more. Rage is gained at the swing (checkpoint R1), so a wrong row on a swing that did land pays the right rage
    -- and no usability answer can tell it; that is not this check's job. A veto (Rows: the swing's answers since it
    -- showed say it gave no rage) is the check applied before the credit: judged and caught.
    it(
        "oracle, party of 5 (in-range melee): catches >= 60% of the rage-false credits it judges (100 fights)",
        function()
            local o = scenarios.oracle({ others = { "melee", "caster" } })
            local m = metrics.fights(o, 100)
            local off = metrics.fights(setmetatable({ oracle = false }, { __index = o }), 100)
            print("\noracle: " .. metrics.oracleLine(m) .. "\nno oracle: " .. metrics.oracleLine(off))
            assert.is_true(m.caught >= 0.60 * m.falseJudged, metrics.oracleLine(m))
            assert.is_true(m.falseRetracted <= 0.01 * (m.right[1] + m.right[2]), metrics.oracleLine(m))
            -- the ladder clamps a false credit's floor at the same poll, with or without the oracle: no poll ever reads
            -- a floor at a cost the true power is below
            assert.is_true(m.danger == 0 and off.danger == 0, metrics.oracleLine(m))
        end
    )
end)
