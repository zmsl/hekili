-- tests/Forever/wowsims_gear_spec.lua (gear-aware spec §4, R35): the replay worlds wear the request's gear.
local ws = require("Forever.helpers.wowsims")

describe("the request's gear", function()
    it("maps by position to client slots, skipping the weapons and trinkets", function()
        local g = ws.gear("druid_balance")
        assert.are.same({ 272430 }, g[18]) -- index 17 (Ranged) -> slot 18: the Swarming Idol
        assert.are.same({ 10250 }, g[1]) -- Head
        assert.is_nil(g[13])
        assert.is_nil(g[14])
        assert.is_nil(g[16])
        assert.is_nil(g[17])
    end)

    it("leaves an oracle-skipped set's pieces unequipped", function()
        local g = ws.gear("druid_balance", { swarming_idol = { 272430 } })
        assert.is_nil(g[18])
    end)

    it("reads the recipe's oracleSkips by default", function()
        assert.are.same(ws.gear("druid_balance", {}), ws.gear("druid_balance")) -- Balance skips nothing
    end)
end)
