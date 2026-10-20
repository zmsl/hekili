-- tests/Forever/retired_packs_spec.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md,
-- Task 1): a built-in pack the class retires (kit:RetirePacks) leaves a saved profile at RestoreDefaults, and a spec
-- that chose it falls back to its default priority; a user's own pack of that name stays.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("retired built-in packs", function()
    it("are dropped from the profile and their specs return to the default priority", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local hk = H.Hekili
        local p = hk.DB.profile
        local id = hk.State.spec.id
        p.packs["Retired Test"] = { builtIn = true, spec = id, version = 1, date = 1, lists = {}, profile = "" }
        p.packs["Mine Test"] = { builtIn = false, spec = id, version = 1, date = 1, lists = {}, profile = "" }
        p.specs[id].package = "Retired Test"
        hk.Class.retiredPacks["Retired Test"] = true
        hk.Class.retiredPacks["Mine Test"] = true
        hk:RestoreDefaults()
        assert.is_nil(rawget(p.packs, "Retired Test"))
        assert.is_not_nil(rawget(p.packs, "Mine Test")) -- not built in: the user's
        assert.are.equal(hk.Class.specs[id].options.package, p.specs[id].package)
    end)

    it("is a kit method the content calls", function()
        local engine = require("Forever.helpers.engine")
        local env = engine.load("WARRIOR")
        env.class.kit:RetirePacks({ "Old A", "Old B" })
        assert.is_true(env.class.retiredPacks["Old A"] and env.class.retiredPacks["Old B"])
    end)
end)
