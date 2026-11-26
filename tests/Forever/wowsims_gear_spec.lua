-- tests/Forever/wowsims_gear_spec.lua (gear-aware spec §4, R35): the replay worlds wear the request's gear.
local ws = require("Forever.helpers.wowsims")

describe("the request's gear", function()
    it("maps by position to client slots, skipping the weapons (the trinkets worn: lane gear-1b)", function()
        local g = ws.gear("druid_balance")
        assert.are.same({ 272430 }, g[18]) -- index 17 (Ranged) -> slot 18: the Swarming Idol
        assert.are.same({ 10250 }, g[1]) -- Head
        assert.are.same({ 272438 }, g[13])
        assert.are.same({ 272439 }, g[14])
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

    it("is worn in every replay: the request's trinket slots (13, 14) where the content wears none", function()
        local c = ws.logged({
            character = function()
                return { items = { [16] = { 1 } } }
            end,
        }, "mage_arcane").character()
        assert.are.same({ [13] = { 22268 }, [14] = { 13968 }, [16] = { 1 } }, c.items)
    end)

    it("a worn trinket is usable to the client", function()
        local headless = require("Game.harness.headless")
        local Hh = headless.new({
            character = { class = "MAGE", classID = 8, level = 60, known = {}, items = { [13] = { 800201 } } },
        })
        assert.is_true(Hh.api.C_Item.IsUsableItem(800201))
        assert.is_false(Hh.api.C_Item.IsUsableItem(800202))
    end)
end)
