-- tests/Game/harness/at_risk_spec.lua: `at_risk` counts the group members below 70% health (absorbs added), the
-- player included; it once counted every living party member (`... < 70 and 1 or 0` as a test: 0 is truthy).
local headless = require("Game.harness.headless")

describe("the at_risk condition", function()
    local H, S, ctl

    setup(function()
        H = headless.new({ raw = { "UnitHealth", "UnitHealthMax", "UnitExists", "UnitIsDeadOrGhost" } })
        S, ctl = H.Hekili.State, H.ctl
    end)

    local function count(party)
        ctl.unitHealth, ctl.unitHealthMax, ctl.exists = {}, {}, {}
        for i, hp in pairs(party) do
            ctl.exists["party" .. i], ctl.unitHealth["party" .. i], ctl.unitHealthMax["party" .. i] = true, hp, 100
        end
        rawset(S, "at_risk", nil)
        return S.at_risk
    end

    it("counts only the low member, not every living one", function()
        assert.are.equal(1, count({ [1] = 30, [2] = 100 }))
    end)

    it("is 0 for a full party", function()
        assert.are.equal(0, count({ [1] = 100, [2] = 100, [3] = 70 }))
    end)

    it("group_health pools party1 too (the loop once started at party2)", function()
        count({ [1] = 100 })
        rawset(S, "group_health", nil)
        local full = S.group_health
        count({ [1] = 10 })
        rawset(S, "group_health", nil)
        assert.is_true(S.group_health < full)
    end)
end)
