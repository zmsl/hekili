-- tests/Forever/health_read_spec.lua (central fix 12 item 2; owner L1461, L1462): the client hides the player's health
-- in combat (UnitHealth and UnitHealthMax "player" secret, plain out of combat; the fake client answers so). A priority
-- line that reads it (`health.pct`) never fires while the client keeps the health secret (unknown reads as full, no
-- compare on a secret) and reads the plain value where the client gives one.
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

    -- the load-time warning (Engine/Sim/AplWarnings.lua), once: H.errors holds the format, ErrorKeys the text
    local warned = { "Forever: %s; `%s` in pack `%s` list `%s` entry %d (%s): %s." }

    it("loads on a Druid with one warning: the player's health is hidden in combat", function()
        assert.are.same(warned, H.errors)
        local text = (
            "Forever: your health is hidden in combat; `health.pct` in pack `%s` list `%s` entry 1"
            .. " (frenzied_regeneration): your health reads full in combat, so a low-health check never passes there."
        ):format(pack, list)
        assert.are.same({ text }, H.Hekili.ErrorKeys)
    end)

    it("the fake client hides the player's health in combat only", function()
        local api, ctl = fake.new()
        ctl.health, ctl.healthMax, ctl.unitHealth.target = 300, 1000, 40
        assert.are.equal(300, api.UnitHealth("player"))
        assert.are.equal(1000, api.UnitHealthMax("player"))
        ctl.combat = true
        assert.is_true(api.issecretvalue(api.UnitHealth("player")))
        assert.is_true(api.issecretvalue(api.UnitHealthMax("player")))
        assert.are.equal(40, api.UnitHealth("target")) -- another unit's row is the test's own
        ctl.combat = false
        assert.are.equal(300, api.UnitHealth("player"))
    end)

    it("reads full in combat, never comparing the secret, and the plain value again after it", function()
        H.ctl.health, H.ctl.healthMax = 300, 1000
        assert.is_true(fires(H.ctl.now + 1)) -- plain (out of combat): 30% < 50
        H.ctl.combat = true
        for i = 2, 4 do
            assert.is_false(fires(H.ctl.now + 1), i)
            assert.are.equal(100, H.Hekili.State.health.pct, i)
        end
        H.ctl.combat = false
        assert.is_true(fires(H.ctl.now + 1))
        assert.are.same(warned, H.errors) -- the load's warning only
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
        assert.are.same(warned, H.errors)
    end)
end)

describe("the loop oracle's raw health rows", function()
    it("read the player's health plain in combat, so no secret reaches the state's arithmetic", function()
        local loop = require("Game.harness.loop")
        local C = dlw.Guardian
        local O = headless.new({ character = C.character(), pack = C.PACK, raw = loop.RAW })
        O.ctl.healthPlain = true -- as loop.new sets it
        O.ctl.combat = true
        for i = 1, 3 do
            assert.is_true(headless.cycle(O, O.ctl.now + 1), i)
        end
        assert.are.same({}, O.errors)
    end)
end)
