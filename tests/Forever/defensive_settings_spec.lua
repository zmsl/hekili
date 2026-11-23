-- tests/Forever/defensive_settings_spec.lua (L1808, owner "Setting per line"): every shipped line that reads the
-- player's health reads its threshold from a per-spec setting (`settings.<action>_health`, a 1-100 slider), default
-- the wowsims or upstream value; a setting every pack reads (Healthstone, the healing potion) comes from the shared
-- content, registered on every spec of the class.
local headless = require("Game.harness.headless")
local dlw = require("Forever.helpers.druid_loop_world")
local ww = require("Forever.helpers.warrior_world")

-- [pack] = { character, { [setting key] = its default } }: def-1's restored lines (L1805) and the shared ones
local PACKS = {
    ["Guardian (wowsims.com)"] = {
        dlw.Guardian.character,
        { barkskin_health = 60, frenzied_regeneration_health = 25 },
    },
    ["Feral (wowsims.com)"] = { -- the imported Guardian lines read the same keys on Feral's own page
        dlw.Feral.character,
        { barkskin_health = 60, frenzied_regeneration_health = 25 },
    },
    ["Protection (wowsims.com)"] = {
        ww.Protection.character,
        {
            last_stand_health = 40,
            shield_wall_health = 35,
            stoneform_health = 50,
            shatter_curse_health = 50,
            healthstone_health = 30,
        },
    },
}

describe("a shared setting", function()
    it("is registered on every spec of the class, the shared content's default (Healthstone 30)", function()
        local H = headless.new({ character = dlw.Guardian.character(), pack = "Guardian (wowsims.com)" })
        local n = 0
        for _, s in ipairs(H.Hekili.Class.kit.trees) do
            if not s.unsupported then
                local found
                for _, e in ipairs(s.settings) do
                    found = found or (e.name == "healthstone_health" and e)
                end
                assert.is_table(found, s.key)
                assert.are.equal(30, found.default)
                n = n + 1
            end
        end
        assert.are.equal(3, n)
    end)
end)

for pack, P in pairs(PACKS) do
    describe("the health settings of " .. pack, function()
        local H

        before_each(function()
            H = headless.new({ character = P[1](), pack = pack })
            assert.are.same({}, H.loadErrors)
        end)

        it("are registered with their default, a 1-100 slider each, and read by the lines", function()
            local S = H.Hekili.State
            local spec = H.Hekili.Class.specs[S.spec.id]
            local byKey = {}
            for _, e in ipairs(spec.settings) do
                byKey[e.name] = e
            end
            local text = {}
            for _, entries in pairs(H.Hekili.DB.profile.packs[pack].lists) do
                for _, e in ipairs(entries) do
                    text[#text + 1] = e.criteria or ""
                end
            end
            text = table.concat(text, "\n")
            for key, default in pairs(P[2]) do
                local e = assert(byKey[key], key)
                assert.are.equal(default, e.default, key)
                assert.are.equal("range", e.info.type, key)
                assert.are.same({ 1, 100 }, { e.info.min, e.info.max }, key)
                assert.are.equal("string", type(e.info.name()), key)
                assert.are.equal(default, S.settings[key], key) -- never nil: `health.pct<=nil` would raise
                assert.is_truthy(text:find("settings%." .. key .. "%f[^%w_]"), key)
            end
            -- no line compares the player's health with a bare number
            assert.is_nil(text:find("[^%w_.]health%.pct[<>=]+%d"))
        end)
    end)
end
