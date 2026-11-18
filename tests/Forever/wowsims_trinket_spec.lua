-- tests/Forever/wowsims_trinket_spec.lua: the recipes whose pinned gear wears the on-use trinket 13968 (wowsims's
-- stat_bonus_cds_auto_gen.go on-use list) map it to use_items, as they map 272438; a recipe wearing it translates to
-- the use_items line.
local apl = require("tools.wowsims.apl")

local SPECS = {
    "mage_arcane",
    "mage_fire",
    "mage_frost",
    "mage_frostfire",
    "shaman_elemental",
    "warlock_destruction",
    "warlock_demonology",
    "warlock_shadow_brand",
    "warlock_sm_ruin",
}

describe("the on-use trinket 13968", function()
    for _, name in ipairs(SPECS) do
        it(name .. " maps it to use_items", function()
            local r = require("tools.wowsims.specs." .. name)
            assert.are.equal("use_items", r.map["item:13968"])
            assert.are.equal("use_items", r.map["item:272438"])
        end)
    end

    it("translates a cast of it to the use_items line", function()
        local kit =
            { abilities = { use_items = { key = "use_items", id = -1, gcd = "off" } }, auras = {}, talents = {} }
        local c = apl.context(kit, { map = { ["item:13968"] = "use_items" } })
        local text, omitted = apl.translate({
            priorityList = { { action = { castSpell = { spellId = { itemId = 13968 } } } } },
        }, c)
        assert.are.equal("actions=use_items,use_off_gcd=1", text)
        assert.are.same({}, omitted)
    end)
end)
