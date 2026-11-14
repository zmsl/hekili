-- tests/Forever/plates_off_warning_spec.lua (L675): in an instance, a spec that counts nameplates with the plate CVars
-- off counts only its target. Engine/Sim/Targets.lua's forced count warns once (on screen and on the Warnings page)
-- when that starts, and again only after it stopped and starts again.
local fake = require("Game.State.helpers.fake_api")
local headless = require("Game.harness.headless")
local wl = require("Forever.helpers.warlock_world")

local KEY = "Enemy nameplates are off, so in this instance Hekili Forever counts only your target. "
    .. "Turn on Show Enemy Nameplates and Show All Nameplates."

describe("the plates-off warning in an instance", function()
    local H, world, notes

    before_each(function()
        world = { instance = true, plates = "0" }
        local new = fake.new
        fake.new = function(...) -- before the Facade resolves GetCVar and IsInInstance
            local api, ctl = new(...)
            api.GetCVar = function(name)
                if name == "nameplateShowEnemies" or name == "nameplateShowAll" then
                    return world.plates
                end
                return ctl.cvars[name]
            end
            api.IsInInstance = function()
                return world.instance, world.instance and "party" or "none"
            end
            return api, ctl
        end
        local ok, res = pcall(headless.new, { character = wl.Destruction.character(), pack = wl.Destruction.PACK })
        fake.new = new
        assert(ok, res)
        H = res
        assert.are.same({}, H.loadErrors)
        notes = 0
        H.Hekili.Notify = function()
            notes = notes + 1
        end
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
    end)

    local function counts(n)
        for _ = 1, n do
            H.ctl.now = H.ctl.now + 0.2
            assert.are.equal(1, H.ns.getNumberTargets(true))
        end
    end

    local function warned()
        local e = H.Hekili.ErrorDB[KEY]
        return e and e.n or 0
    end

    it("warns once while it holds, and again after the plates were on", function()
        counts(5)
        assert.are.equal(1, notes)
        assert.are.equal(1, warned())
        world.plates = "1"
        counts(2)
        world.plates = "0"
        counts(3)
        assert.are.equal(2, notes)
        assert.are.equal(2, warned())
    end)

    it("does not warn outside an instance", function()
        world.instance = false
        counts(3)
        assert.are.equal(0, notes)
        assert.are.equal(0, warned())
    end)

    it("does not warn when the spec does not count nameplates", function()
        H.Hekili.DB.profile.specs[wl.Destruction.SPEC].nameplates = false
        counts(3)
        assert.are.equal(0, notes)
        assert.are.equal(0, warned())
    end)

    it("does not warn with the plates on", function()
        world.plates = "1"
        counts(3)
        assert.are.equal(0, notes)
    end)
end)
