-- tests/Game/harness/onus_spec.lua (harness design §4.3): hits on us from two attackers through the real
-- Attackers.lua (their speeds secret: clocks from the gaps), and every hit reaching the belief as a PlayerHit,
-- attributed or not (§4.4).
local metrics = require("Game.harness.metrics")
local ab = require("Game.harness.ab") -- the bars: asserted in the default arm, recorded in a provider arm (§4.1)

local function mobs(a, b)
    return { { damage = a, period = 2.0 }, { damage = b, period = 2.6 } }
end

describe("hits on us (harness gates) #slow", function()
    it(
        "two attackers of 2x different strength, the second joining at 15 s: precision >= 0.95, coverage >= 0.80",
        function()
            local m = metrics.fights({ attackers = 2, joinAt = { [2] = 15 }, mobs = mobs({ 10, 14 }, { 20, 28 }) }, 100)
            local line = metrics.onusLine(m)
            ab.check(m.onusRight >= 0.95 * m.onusCredited and m.onusCredited >= 0.80 * m.onusAll, "onus", line)
            assert.are.equal(m.hitsFed, m.hitsStaged)
        end
    )

    it("two attackers of the same strength on us from the pull: precision >= 0.90, coverage reported", function()
        local m = metrics.fights({ attackers = 2, mobs = mobs({ 10, 14 }, { 10, 14 }) }, 100)
        print("\nsame strength, from the pull: " .. metrics.onusLine(m))
        ab.check(m.onusCredited == 0, "onus", metrics.onusLine(m)) -- no clock starts while two are on us
        assert.are.equal(m.hitsFed, m.hitsStaged)
    end)

    it(
        "two of the same strength, the second joining at 15 s: reported (the first one's clock takes some of its hits)",
        function()
            local m = metrics.fights({ attackers = 2, joinAt = { [2] = 15 }, mobs = mobs({ 10, 14 }, { 10, 14 }) }, 30)
            print("\nsame strength, the second joining: " .. metrics.onusLine(m))
            assert.are.equal(m.hitsFed, m.hitsStaged)
        end
    )
end)
