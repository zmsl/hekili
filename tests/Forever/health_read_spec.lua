-- tests/Forever/health_read_spec.lua (central fix 12 item 2): a priority line that reads the player's health
-- (`health.pct`, wowsims's currentHealthPercent) loads without an error, never fires while the client keeps the
-- health secret (unknown reads as full) and reads the plain value where the client gives one.
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")
local dlw = require("Forever.helpers.druid_loop_world")

describe("a player health read in a priority", function()
    local H, scriptID, pack, list
    setup(function()
        local C = dlw.Guardian
        H = headless.new({ character = C.character(), pack = C.PACK })
        pack = C.PACK
        local lists = H.Hekili.DB.profile.packs[pack].lists
        list = next(lists)
        table.insert(lists[list], 1, { action = "frenzied_regeneration", criteria = "health.pct<50", enabled = true })
        H.Hekili:LoadScripts()
        scriptID = pack .. ":" .. list .. ":1"
    end)

    local function fires(t)
        assert.is_true(headless.cycle(H, t))
        H.Hekili.State.reset()
        return H.Hekili.Scripts:CheckScript(scriptID)
    end

    it("loads on a Druid without an error", function()
        assert.are.same({}, H.errors)
    end)

    it("never fires while the client keeps the health secret, and honours a plain read", function()
        H.ctl.health, H.ctl.healthMax = 300, 1000
        assert.is_true(fires(H.ctl.now + 1)) -- plain (out of combat): 30% < 50
        H.ctl.unitHealth.player = fake.SECRET -- secret: unknown reads as full
        for i = 2, 5 do
            assert.is_false(fires(H.ctl.now + 1), i)
        end
        H.ctl.unitHealth.player = 900
        assert.is_false(fires(H.ctl.now + 1))
        H.ctl.unitHealth.player = 200
        assert.is_true(fires(H.ctl.now + 1))
        assert.are.same({}, H.errors)
    end)
end)
