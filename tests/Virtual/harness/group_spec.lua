-- tests/Virtual/harness/group_spec.lua (harness design §3.4, decisions D4-D5): other sources on our target (G fact 1:
-- their outcomes arrive on our target's tokens with plain amounts), through the real Rows.lua; the gates of §3.4. The
-- raid is reported, not gated (D5).
local metrics = require("Virtual.harness.metrics")

local function check(ok, m)
    assert.is_true(ok, metrics.line(m))
end

describe("group attribution (harness gates) #slow", function()
    it("party of 5, a melee in our main range and a caster on our target (100 fights)", function()
        local m = metrics.fights({ others = { "melee", "caster" } }, 100)
        check(metrics.rate(m, 1) >= 0.75 and metrics.rate(m, 2) >= 0.85, m)
        check(metrics.falsePer100(m) <= 4 and m.over <= 0.05 * m.windows, m)
    end)

    it("party of 5 with a pet and a ranged stand-in on our target as well (100 fights)", function()
        local m = metrics.fights({ others = { "melee", "caster", "pet", "ranged" } }, 100)
        check(metrics.rate(m, 1) >= 0.70 and metrics.rate(m, 2) >= 0.70, m)
        check(metrics.falsePer100(m) <= 6 and m.over <= 0.10 * m.windows, m)
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
end)
