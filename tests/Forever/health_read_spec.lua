-- tests/Forever/health_read_spec.lua (central fix 12 item 2; owner L1461, L1462): the client hides the player's health
-- in combat (UnitHealth and UnitHealthMax "player" secret, plain out of combat; the fake client answers so). Without the
-- hidden-value library a priority line that reads it (`health.pct`) never fires while the client keeps the health
-- secret (unknown reads as full, no compare on a secret) and reads the plain value where the client gives one. With
-- the library's band (lane B3, integration design 2.5) it reads the band's middle in combat. No load-time warning
-- either way (FABLE-FOR-OWNER 7: the own-health rows of Engine/Sim/AplWarnings.lua are gone).
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

    -- no load-time warning (FABLE-FOR-OWNER 7): H.errors holds none
    local warned = {}

    it("loads on a Druid with no warning: the player's health is no longer a dead read", function()
        assert.are.same(warned, H.errors)
        assert.are.same({}, H.Hekili.ErrorKeys)
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
        assert.are.same(warned, H.errors)
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

-- Lane B3: the band source (Sources/Bands.lua) on the harness's fake library (fake_lhv.lua, in the instance's LibStub as
-- the loop's bands arms install it); the band answers 11 frames after the watch, a change 2 frames after it fires.
describe("a player health read in a priority, with the hidden-value band (lane B3)", function()
    local fake_lhv = require("Game.harness.fake_lhv")
    local F = 1 / 60
    local H, scriptID, lhv

    setup(function()
        local C = dlw.Guardian
        H = headless.new({ character = C.character(), pack = C.PACK })
        lhv = fake_lhv.new({
            now = function()
                return H.ctl.now
            end,
        })
        local major, minor = lhv:GetVersion()
        local stub = rawget(H.env, "LibStub")
        stub.libs[major], stub.minors[major] = lhv, minor
        H.Hekili.bandOff = false
        H.Hekili:ProvidersChanged()
        local lists = H.Hekili.DB.profile.packs[C.PACK].lists
        local list = next(lists)
        table.insert(lists[list], 1, { action = "frenzied_regeneration", criteria = "health.pct<50", enabled = true })
        H.Hekili:LoadScripts()
        scriptID = C.PACK .. ":" .. list .. ":1"
    end)

    -- n frames, a cycle each; whether the line fires after the last, and the state's health.pct then
    local function frames(n)
        for i = 1, n do
            assert.is_true(headless.cycle(H, H.ctl.now + F), i)
        end
        H.Hekili.State.reset()
        return H.Hekili.Scripts:CheckScript(scriptID), H.Hekili.State.health.pct
    end

    local function push(hp)
        lhv:Push("health", "player", nil, hp, 1000, H.ctl.now)
    end

    it("fires in combat on the band's middle, follows a heal, and reads full once the band is lost", function()
        H.ctl.health, H.ctl.healthMax = 1000, 1000
        push(1000)
        assert.are.same({ false, 100 }, { frames(14) })
        H.ctl.combat = true
        H.ctl.Fire("PLAYER_REGEN_DISABLED")
        push(455)
        assert.are.same({ true, 45.5 }, { frames(3) })
        push(505) -- a heal
        assert.are.same({ false, 50.5 }, { frames(3) })
        push(495)
        assert.are.same({ true, 49.5 }, { frames(3) })
        lhv:SetAvailable("unavailable", "error") -- the capability lost: today's "unknown", full
        assert.are.same({ false, 100 }, { frames(3) })
        assert.are.same({}, H.errors)
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
