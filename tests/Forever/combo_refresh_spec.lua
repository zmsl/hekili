-- tests/Forever/combo_refresh_spec.lua: the Rogue and Druid packs force a refresh when the player's combo points change
-- (UNIT_POWER_FREQUENT with the "COMBO_POINTS" token), and for no other power token.
local ld = require("Forever.helpers.load_druid")

describe("combo point refresh", function()
    for _, c in ipairs({
        { "Rogue", "src/Hekili_Rogue/Rogue.lua", "ROGUE" },
        { "Druid", "src/Hekili_Druid/Druid.lua", "DRUID" },
    }) do
        it(c[1] .. " forces one update for COMBO_POINTS and none for another token", function()
            local w = ld.load(nil, c[2], c[3])
            local hs = w.unitEvents.UNIT_POWER_FREQUENT
            assert.is_table(hs)
            assert.equals(1, #hs)
            local forced = {}
            local saved = rawget(_G, "Hekili")
            _G.Hekili = {
                ForceUpdate = function(_, ...)
                    forced[#forced + 1] = { ... }
                end,
            }
            hs[1]("UNIT_POWER_FREQUENT", "player", "ENERGY")
            hs[1]("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
            _G.Hekili = saved
            assert.equals(1, #forced)
            assert.equals("COMBO_POINTS", forced[1][1])
            assert.is_true(forced[1][2])
        end)
    end
end)
